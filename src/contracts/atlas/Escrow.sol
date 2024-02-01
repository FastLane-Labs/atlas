//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import { AtlasVerification } from "./AtlasVerification.sol";
import { AtlETH } from "./AtlETH.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import { DAppConfig } from "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

import { EscrowBits } from "../libraries/EscrowBits.sol";
import { CallBits } from "../libraries/CallBits.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

// import "forge-std/Test.sol";

abstract contract Escrow is AtlETH {
    using ECDSA for bytes32;
    using EscrowBits for uint256;
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    event PreOpsCall(address environment, bool success, bytes returnData);
    event UserCall(address environment, bool success, bytes returnData);
    event PostOpsCall(address environment, bool success); // No return data tracking for post ops?

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        AtlETH(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    function _executePreOpsCall(
        UserOperation calldata userOp,
        address environment,
        bytes32 lockBytes
    )
        internal
        returns (bool success, bytes memory preOpsData)
    {
        preOpsData = abi.encodeWithSelector(IExecutionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, lockBytes);
        (success, preOpsData) = environment.call(preOpsData);
        if (success) {
            preOpsData = abi.decode(preOpsData, (bytes));
        }
        emit PreOpsCall(environment, success, preOpsData);
    }

    function _executeUserOperation(
        UserOperation calldata userOp,
        address environment,
        bytes32 lockBytes
    )
        internal
        returns (bool success, bytes memory userData)
    {
        userData = abi.encodeWithSelector(IExecutionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, lockBytes);

        (success, userData) = environment.call{ value: userOp.value }(userData);

        // require(success, "ERR-E002 UserFail");
        if (success) {
            userData = abi.decode(userData, (bytes));
        }

        emit UserCall(environment, success, userData);
    }

    function _executeSolverOperation(
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        address environment,
        EscrowKey memory key
    )
        internal
        returns (bool auctionWon, EscrowKey memory)
    {
        // Set the gas baseline
        uint256 gasWaterMark = gasleft();

        // Verify the transaction.
        (uint256 result, uint256 gasLimit) = _validateSolverOperation(solverOp);

        // If there are no errors, attempt to execute
        if (result.canExecute() && _trySolverLock(solverOp)) {
            // Open the solver lock
            key = key.holdSolverLock(solverOp.solver);

            // Execute the solver call
            // _solverOpsWrapper returns a SolverOutcome enum value
            result |= 1 << _solverOpWrapper(gasLimit, environment, solverOp, dAppReturnData, key.pack());

            if (result.executionSuccessful()) {
                // first successful solver call that paid what it bid
                result |= 1 << uint256(SolverOutcome.ExecutionCompleted);
                emit SolverTxResult(solverOp.solver, solverOp.from, true, true, result);

                // winning solver's gas is implicitly paid for by their allowance
                return (true, key.turnSolverLockPayments(environment));
            } else {
                _releaseSolverLock(solverOp, gasWaterMark, result);
                result |= 1 << uint256(SolverOutcome.ExecutionCompleted);

                // emit event
                emit SolverTxResult(solverOp.solver, solverOp.from, true, false, result);
            }
        } else {
            _releaseSolverLock(solverOp, gasWaterMark, result);

            // emit event
            emit SolverTxResult(solverOp.solver, solverOp.from, false, false, result);
        }
        return (auctionWon, key);
    }

    // TODO: who should pay gas cost of MEV Payments?
    // TODO: Should payment failure trigger subsequent solver calls?
    // (Note that balances are held in the execution environment, meaning
    // that payment failure is typically a result of a flaw in the
    // DAppControl contract)
    function _allocateValue(
        DAppConfig calldata dConfig,
        uint256 winningBidAmount,
        bytes memory returnData,
        address environment,
        bytes32 lockBytes
    )
        internal
        returns (bool success)
    {
        // process dApp payments
        bytes memory data = abi.encodeWithSelector(
            IExecutionEnvironment.allocateValue.selector, dConfig.bidToken, winningBidAmount, returnData
        );
        data = abi.encodePacked(data, lockBytes);
        (success,) = environment.call(data);
        if (!success) {
            emit MEVPaymentFailure(dConfig.to, dConfig.callConfig, dConfig.bidToken, winningBidAmount);
        }
    }

    function _executePostOpsCall(
        bool solved,
        bytes memory returnData,
        address environment,
        bytes32 lockBytes
    )
        internal
        returns (bool success)
    {
        bytes memory postOpsData =
            abi.encodeWithSelector(IExecutionEnvironment.postOpsWrapper.selector, solved, returnData);
        postOpsData = abi.encodePacked(postOpsData, lockBytes);
        (success,) = environment.call(postOpsData);
        emit PostOpsCall(environment, success);
    }

    // TODO Revisit the EscrowAccountBalance memory solverEscrow arg. Needs to be passed through from Atlas, through
    // callstack
    function _validateSolverOperation(SolverOperation calldata solverOp)
        internal
        view
        returns (uint256 result, uint256 gasLimit)
    {
        // Set the gas baseline
        uint256 gasWaterMark = gasleft();

        EscrowAccountAccessData memory aData = accessData[solverOp.from];

        uint256 solverBalance = aData.bonded;
        uint256 lastAccessedBlock = aData.lastAccessedBlock;

        if (solverOp.to != address(this)) {
            result |= 1 << uint256(SolverOutcome.InvalidTo);
        }

        // NOTE: Turn this into time stamp check for FCFS L2s?
        if (lastAccessedBlock == block.number) {
            result |= 1 << uint256(SolverOutcome.PerBlockLimit);
        }

        gasLimit = (100) * (solverOp.gas < EscrowBits.SOLVER_GAS_LIMIT ? solverOp.gas : EscrowBits.SOLVER_GAS_LIMIT)
            / (100 + EscrowBits.SOLVER_GAS_BUFFER) + EscrowBits.FASTLANE_GAS_BUFFER;

        uint256 gasCost = (tx.gasprice * gasLimit) + (solverOp.data.length * CALLDATA_LENGTH_PREMIUM * tx.gasprice);

        // see if solver's escrow can afford tx gascost
        if (gasCost > solverBalance) {
            // charge solver for calldata so that we can avoid vampire attacks from solver onto user
            result |= 1 << uint256(SolverOutcome.InsufficientEscrow);
        }

        // Verify that we can lend the solver their tx value
        if (
            solverOp.value
                > address(this).balance - (gasLimit * tx.gasprice > address(this).balance ? 0 : gasLimit * tx.gasprice)
        ) {
            result |= 1 << uint256(SolverOutcome.CallValueTooHigh);
        }

        // subtract out the gas buffer since the solver's metaTx won't use it
        gasLimit -= EscrowBits.FASTLANE_GAS_BUFFER;

        if (gasWaterMark < EscrowBits.VALIDATION_GAS_LIMIT + EscrowBits.SOLVER_GAS_LIMIT) {
            // Make sure to leave enough gas for dApp validation calls
            result |= 1 << uint256(SolverOutcome.UserOutOfGas);
        }

        return (result, gasLimit);
    }

    // Returns a SolverOutcome enum value
    function _solverOpWrapper(
        uint256 gasLimit,
        address environment,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        bytes32 lockBytes
    )
        internal
        returns (uint256)
    {
        // address(this) = Atlas/Escrow
        // msg.sender = tx.origin

        bool success;

        bytes memory data = abi.encodeWithSelector(
            IExecutionEnvironment(environment).solverMetaTryCatch.selector, gasLimit, solverOp, dAppReturnData
        );

        data = abi.encodePacked(data, lockBytes);

        (success, data) = environment.call{ value: solverOp.value }(data);

        if (success) {
            return uint256(SolverOutcome.Success);
        }
        bytes4 errorSwitch = bytes4(data);

        if (errorSwitch == SolverBidUnpaid.selector) {
            return uint256(SolverOutcome.BidNotPaid);
        } else if (errorSwitch == SolverMsgValueUnpaid.selector) {
            return uint256(SolverOutcome.CallValueTooHigh);
        } else if (errorSwitch == IntentUnfulfilled.selector) {
            return uint256(SolverOutcome.IntentUnfulfilled);
        } else if (errorSwitch == SolverOperationReverted.selector) {
            return uint256(SolverOutcome.CallReverted);
        } else if (errorSwitch == AlteredControlHash.selector) {
            return uint256(SolverOutcome.InvalidControlHash);
        } else if (errorSwitch == PreSolverFailed.selector) {
            return uint256(SolverOutcome.PreSolverFailed);
        } else if (errorSwitch == PostSolverFailed.selector) {
            return uint256(SolverOutcome.IntentUnfulfilled);
        } else {
            return uint256(SolverOutcome.CallReverted);
        }
    }

    receive() external payable { }

    fallback() external payable {
        revert(); // no untracked balance transfers plz. (not that this fully stops it)
    }
}
