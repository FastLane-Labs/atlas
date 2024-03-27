//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";
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

    // Returns (bool auctionWon, EscrowKey key)
    function _executeSolverOperation(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        address environment,
        address bundler,
        bytes32 userOpHash,
        EscrowKey memory key
    )
        internal
        returns (bool, EscrowKey memory)
    {
        // Set the gas baseline
        uint256 gasWaterMark = gasleft();
        uint256 result =
            IAtlasVerification(VERIFICATION).verifySolverOp(solverOp, userOpHash, userOp.maxFeePerGas, bundler);

        // Verify the transaction.
        if (result.canExecute()) {
            uint256 gasLimit;
            (result, gasLimit) = _validateSolverOperation(dConfig, solverOp, gasWaterMark, result);

            if (dConfig.callConfig.allowsTrustedOpHash()) {
                key.solverOutcome = result;
                if (!_handleAltOpHash(userOp, solverOp)) return (false, key);
            }

            // If there are no errors, attempt to execute
            if (result.canExecute() && _trySolverLock(solverOp)) {
                // Open the solver lock
                key = key.holdSolverLock(solverOp.solver);

                // Execute the solver call
                // _solverOpsWrapper returns a SolverOutcome enum value
                result |= _solverOpWrapper(gasLimit, environment, solverOp, dAppReturnData, key.pack());

                key.solverOutcome = result;

                if (result.executionSuccessful()) {
                    // first successful solver call that paid what it bid

                    emit SolverTxResult(solverOp.solver, solverOp.from, true, true, result);

                    key.solverSuccessful = true;
                    // auctionWon = true
                    return (true, key);
                }
            }
        }

        key.solverOutcome = result;

        _releaseSolverLock(solverOp, gasWaterMark, result);

        unchecked {
            ++key.callIndex;
        }
        // emit event
        emit SolverTxResult(solverOp.solver, solverOp.from, result.executedWithError(), false, result);

        // auctionWon = false
        return (false, key);
    }

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
    function _validateSolverOperation(
        DAppConfig calldata dConfig,
        SolverOperation calldata solverOp,
        uint256 gasWaterMark,
        uint256 result
    )
        internal
        view
        returns (uint256, uint256 gasLimit)
    {
        if (gasWaterMark < EscrowBits.VALIDATION_GAS_LIMIT + dConfig.solverGasLimit) {
            // Make sure to leave enough gas for dApp validation calls
            return (result | 1 << uint256(SolverOutcome.UserOutOfGas), gasLimit);
        }

        if (block.number > solverOp.deadline) {
            return (
                result
                    | 1
                        << uint256(
                            dConfig.callConfig.allowsTrustedOpHash()
                                ? uint256(SolverOutcome.DeadlinePassedAlt)
                                : uint256(SolverOutcome.DeadlinePassed)
                        ),
                0
            );
        }

        gasLimit = (100) * (solverOp.gas < dConfig.solverGasLimit ? solverOp.gas : dConfig.solverGasLimit)
            / (100 + EscrowBits.SOLVER_GAS_BUFFER) + EscrowBits.FASTLANE_GAS_BUFFER;

        uint256 gasCost = (tx.gasprice * gasLimit) + (solverOp.data.length * CALLDATA_LENGTH_PREMIUM * tx.gasprice);

        // Verify that we can lend the solver their tx value
        if (
            solverOp.value
                > address(this).balance - (gasLimit * tx.gasprice > address(this).balance ? 0 : gasLimit * tx.gasprice)
        ) {
            return (result |= 1 << uint256(SolverOutcome.CallValueTooHigh), gasLimit);
        }

        // subtract out the gas buffer since the solver's metaTx won't use it
        gasLimit -= EscrowBits.FASTLANE_GAS_BUFFER;

        EscrowAccountAccessData memory aData = accessData[solverOp.from];

        uint256 solverBalance = aData.bonded;
        uint256 lastAccessedBlock = aData.lastAccessedBlock;

        // NOTE: Turn this into time stamp check for FCFS L2s?
        if (lastAccessedBlock == block.number) {
            result |= 1 << uint256(SolverOutcome.PerBlockLimit);
        }

        // see if solver's escrow can afford tx gascost
        if (gasCost > solverBalance) {
            // charge solver for calldata so that we can avoid vampire attacks from solver onto user
            result |= 1 << uint256(SolverOutcome.InsufficientEscrow);
        }

        return (result, gasLimit);
    }

    function _handleAltOpHash(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        internal
        returns (bool)
    {
        // These failures should be attributed to bundler maliciousness
        if (solverOp.deadline != userOp.deadline || solverOp.control != userOp.control) {
            return false;
        }
        bytes32 hashId = keccak256(abi.encodePacked(solverOp.userOpHash, solverOp.from, solverOp.deadline));
        if (_solverOpHashes[hashId]) {
            return false;
        }
        _solverOpHashes[hashId] = true;
        return true;
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
            return uint256(0);
        }
        bytes4 errorSwitch = bytes4(data);

        if (errorSwitch == AlteredControl.selector) {
            return 1 << uint256(SolverOutcome.AlteredControl);
        } else if (errorSwitch == PreSolverFailed.selector) {
            return 1 << uint256(SolverOutcome.PreSolverFailed);
        } else if (errorSwitch == SolverOperationReverted.selector) {
            return 1 << uint256(SolverOutcome.SolverOpReverted);
        } else if (errorSwitch == PostSolverFailed.selector) {
            return 1 << uint256(SolverOutcome.PostSolverFailed);
        } else if (errorSwitch == IntentUnfulfilled.selector) {
            return 1 << uint256(SolverOutcome.IntentUnfulfilled);
        } else if (errorSwitch == SolverBidUnpaid.selector) {
            return 1 << uint256(SolverOutcome.BidNotPaid);
        } else if (errorSwitch == BalanceNotReconciled.selector) {
            return 1 << uint256(SolverOutcome.BalanceNotReconciled);
        } else {
            return 1 << uint256(SolverOutcome.EVMError);
        }
    }

    receive() external payable { }

    fallback() external payable {
        revert(); // no untracked balance transfers plz. (not that this fully stops it)
    }
}
