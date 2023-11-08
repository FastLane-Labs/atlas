//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";
import {IAtlasVerification} from "../interfaces/IAtlasVerification.sol";

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {AtlasVerification} from "./AtlasVerification.sol";
import {AtlETH} from "./AtlETH.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import {DAppConfig} from "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

import {EscrowBits} from "../libraries/EscrowBits.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

abstract contract Escrow is AtlETH {
    using ECDSA for bytes32;
    using EscrowBits for uint256;
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _simulator
    ) AtlETH(_escrowDuration, _factory, _verification, _gasAccLib, _simulator) {}

    ///////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS FOR BUNDLER INTERACTION  ///
    ///////////////////////////////////////////////////

    ///////////////////////////////////////////////////
    ///             INTERNAL FUNCTIONS              ///
    ///////////////////////////////////////////////////
    function _executePreOpsCall(UserOperation calldata userOp, address environment, bytes32 lockBytes)
        internal
        returns (bool success, bytes memory preOpsData)
    {
        preOpsData = abi.encodeWithSelector(IExecutionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, lockBytes);
        (success, preOpsData) = environment.call{value: msg.value}(preOpsData);
        if (success) {
            preOpsData = abi.decode(preOpsData, (bytes));
        }
    }

    function _executeUserOperation(UserOperation calldata userOp, address environment, bytes32 lockBytes)
        internal
        returns (bool success, bytes memory userData)
    {
        userData = abi.encodeWithSelector(IExecutionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, lockBytes);

        if (userOp.value > 0) {
            _use(Party.User, userOp.from, userOp.value);
            (success, userData) = environment.call{value: userOp.value}(userData);
        } else {
            (success, userData) = environment.call(userData);
        }
        // require(success, "ERR-E002 UserFail");
        if (success) {
            userData = abi.decode(userData, (bytes));
        }
    }

    function _executeSolverOperation(
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        address environment,
        address bundler,
        EscrowKey memory key
    ) internal returns (bool auctionWon, EscrowKey memory) {
        
        // Set the gas baseline
        uint256 gasWaterMark = gasleft();

        EscrowAccountData memory solverEscrow = _escrowAccountData[solverOp.from];
        uint256 result;
        uint256 gasLimit;

        // Verify the transaction.
        (result, gasLimit, solverEscrow) =
            IAtlasVerification(VERIFICATION).verifySolverOp(solverOp, solverEscrow, gasWaterMark, false);

        // If there are no errors, attempt to execute
        if (result.canExecute() && _checkSolverProxy(solverOp.from, bundler)) {
            // Open the solver lock
            key = key.holdSolverLock(solverOp.solver);

            if (solverOp.value != 0) {
                _borrow(Party.Solver, solverOp.value);
            }

            // Execute the solver call
            // _solverOpsWrapper returns a SolverOutcome enum value
            result |= 1 << _solverOpWrapper(gasLimit, environment, solverOp, dAppReturnData, key.pack());

            if (result.executionSuccessful()) {
                // first successful solver call that paid what it bid
                result |= 1 << uint256(SolverOutcome.ExecutionCompleted);
                emit SolverTxResult(
                    solverOp.solver, solverOp.from, true, true, solverEscrow.nonce, result
                );

                _updateSolverProxy(solverOp.from, bundler, true);

                // winning solver's gas is implicitly paid for by their allowance
                return (true, key.turnSolverLockPayments(environment));
            
            } else if (solverOp.value != 0) {
                _tradeCorrection(Party.Solver, solverOp.value);
            }

            

            _updateSolverProxy(solverOp.from, bundler, false);
            result |= 1 << uint256(SolverOutcome.ExecutionCompleted);

            // Update the solver's escrow balances and the accumulated refund
            if (result.updateEscrow()) {
                key.gasRefund += uint32(_update(solverOp, solverEscrow, gasWaterMark, result));
            }

            // emit event
            emit SolverTxResult(
                solverOp.solver, solverOp.from, true, false, solverEscrow.nonce, result
            );
        } else {
            // emit event
            emit SolverTxResult(solverOp.solver, solverOp.from, false, false, solverEscrow.nonce, result);
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
    ) internal returns (bool success) {
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

    function _executePostOpsCall(bytes memory returnData, address environment, bytes32 lockBytes)
        internal
        returns (bool success)
    {
        bytes memory postOpsData = abi.encodeWithSelector(IExecutionEnvironment.postOpsWrapper.selector, returnData);
        postOpsData = abi.encodePacked(postOpsData, lockBytes);
        (success,) = environment.call{value: msg.value}(postOpsData);
    }

    function _update(
        SolverOperation calldata solverOp,
        EscrowAccountData memory solverEscrow,
        uint256 gasWaterMark,
        uint256 result
    ) internal returns (uint256 gasRebate) {
        unchecked {
            uint256 gasUsed = gasWaterMark - gasleft();

            if (result & EscrowBits._FULL_REFUND != 0) {
                gasRebate = gasUsed + (solverOp.data.length * CALLDATA_LENGTH_PREMIUM);
            } else if (result & EscrowBits._CALLDATA_REFUND != 0) {
                gasRebate = (solverOp.data.length * CALLDATA_LENGTH_PREMIUM);
            } else if (result & EscrowBits._NO_USER_REFUND != 0) {
                // pass
            } else {
                revert UncoveredResult();
            }

            if (gasRebate != 0) {
                // Calculate what the solver owes
                gasRebate *= tx.gasprice;

                gasRebate = gasRebate > solverEscrow.balance ? solverEscrow.balance : gasRebate;

                solverEscrow.balance -= uint128(gasRebate);

                // NOTE: This will cause an error if you are simulating with a gasPrice of 0
                gasRebate /= tx.gasprice;

                // Save the escrow data back into storage
                _escrowAccountData[solverOp.from] = solverEscrow;

                // Check if need to save escrowData due to nonce update but not gasRebate
            } else if (result & EscrowBits._NO_NONCE_UPDATE == 0) {
                _escrowAccountData[solverOp.from].nonce = solverEscrow.nonce;
            }
        }
    }

    // Returns a SolverOutcome enum value
    function _solverOpWrapper(
        uint256 gasLimit,
        address environment,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        bytes32 lockBytes
    ) internal returns (uint256) {
        // address(this) = Atlas/Escrow
        // msg.sender = tx.origin

        bool success;

        bytes memory data = abi.encodeWithSelector(
            IExecutionEnvironment(environment).solverMetaTryCatch.selector,
            gasLimit,
            solverOp,
            dAppReturnData
        );

        data = abi.encodePacked(data, lockBytes);

        (success, data) = environment.call{value: solverOp.value}(data);

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
        } else if (errorSwitch == SolverFailedCallback.selector) {
            return uint256(SolverOutcome.CallbackFailed);
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

    receive() external payable {}

    fallback() external payable {
        revert(); // no untracked balance transfers plz. (not that this fully stops it)
    }
}
