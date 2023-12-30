//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { Escrow } from "./Escrow.sol";
import { Factory } from "./Factory.sol";

import { UserSimulationFailed, UserUnexpectedSuccess, UserSimulationSucceeded } from "../types/Emissions.sol";

import { FastLaneErrorsEvents } from "../types/Emissions.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/LockTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/ValidCallsTypes.sol";

import { CALLDATA_LENGTH_PREMIUM } from "../types/EscrowTypes.sol";

import { CallBits } from "../libraries/CallBits.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Atlas is Escrow, Factory {
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _executionTemplate
    )
        Escrow(_escrowDuration, _verification, _simulator)
        Factory(_executionTemplate)
    { }

    function metacall( // <- Entrypoint Function
        UserOperation calldata userOp, // set by user
        SolverOperation[] memory solverOps, // supplied by FastLane via frontend integration
        DAppOperation calldata dAppOp // supplied by front end after it sees the other data
    )
        external
        payable
        returns (bool auctionWon)
    {
        uint256 gasMarker = gasleft(); // + 21_000 + (msg.data.length * CALLDATA_LENGTH_PREMIUM);

        // Get or create the execution environment
        address executionEnvironment;
        DAppConfig memory dConfig;
        (executionEnvironment, dConfig) = _getOrCreateExecutionEnvironment(userOp);

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        // NOTE: Currently reverting instead of graceful return to help w/ testing.
        ValidCallsResult validCallsResult;
        (solverOps, validCallsResult) = IAtlasVerification(VERIFICATION).validCalls(
            dConfig, userOp, solverOps, dAppOp, msg.value, msg.sender, msg.sender == SIMULATOR
        );
        if (validCallsResult != ValidCallsResult.Valid) {
            if (msg.sender == SIMULATOR) revert VerificationSimFail();
            else revert ValidCalls(validCallsResult);
        }

        // Initialize the lock
        _initializeEscrowLock(executionEnvironment, gasMarker, userOp.value);

        try this.execute{ value: msg.value }(dConfig, userOp, solverOps, executionEnvironment, msg.sender) returns (
            bool _auctionWon, uint256 winningSolverIndex
        ) {
            auctionWon = _auctionWon;
            // Gas Refund to sender only if execution is successful
            _settle({ winningSolver: auctionWon ? solverOps[winningSolverIndex].from : msg.sender, bundler: msg.sender });
        } catch (bytes memory revertData) {
            // Bubble up some specific errors
            _handleErrors(bytes4(revertData), dConfig.callConfig);
        }

        // Release the lock
        _releaseEscrowLock();

        console.log("total gas used", gasMarker - gasleft());
    }

    function execute(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        address executionEnvironment,
        address bundler
    )
        external
        payable
        returns (bool auctionWon, uint256 winningSearcherIndex)
    {
        // This is a self.call made externally so that it can be used with try/catch
        if (msg.sender != address(this)) revert InvalidAccess();

        // Build the memory lock
        EscrowKey memory key =
            _buildEscrowLock(dConfig, executionEnvironment, uint8(solverOps.length), bundler == SIMULATOR);

        // Begin execution
        (auctionWon, winningSearcherIndex) = _execute(dConfig, userOp, solverOps, executionEnvironment, key);
    }

    function _execute(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        address executionEnvironment,
        EscrowKey memory key
    )
        internal
        returns (bool auctionWon, uint256 winningSearcherIndex)
    {
        // Build the CallChainProof.  The penultimate hash will be used
        // to verify against the hash supplied by DAppControl

        bool callSuccessful;

        bytes memory returnData;

        if (dConfig.callConfig.needsPreOpsCall()) {
            key = key.holdPreOpsLock(dConfig.to);
            (callSuccessful, returnData) = _executePreOpsCall(userOp, executionEnvironment, key.pack());
            if (!callSuccessful) {
                if (key.isSimulation) revert PreOpsSimFail();
                else revert PreOpsFail();
            }
        }

        key = key.holdUserLock(userOp.dapp);

        bytes memory userReturnData;
        (callSuccessful, userReturnData) = _executeUserOperation(userOp, executionEnvironment, key.pack());
        if (!callSuccessful) {
            if (key.isSimulation) revert UserOpSimFail();
            else revert UserOpFail();
        }

        if (CallBits.needsPreOpsReturnData(dConfig.callConfig)) {
            //returnData = returnData;
            if (CallBits.needsUserReturnData(dConfig.callConfig)) {
                returnData = bytes.concat(returnData, userReturnData);
            }
        } else if (CallBits.needsUserReturnData(dConfig.callConfig)) {
            returnData = userReturnData;
        }

        for (; winningSearcherIndex < solverOps.length;) {
            // valid solverOps are packed from left of array - break at first invalid solverOp
            if (solverOps[winningSearcherIndex].from == address(0)) break;

            (auctionWon, key) = _solverExecutionIteration(
                dConfig, solverOps[winningSearcherIndex], returnData, auctionWon, executionEnvironment, key
            );
            if (auctionWon) break;

            unchecked {
                ++winningSearcherIndex;
            }
        }

        // If no solver was successful, manually transition the lock
        if (!auctionWon) {
            if (key.isSimulation) revert SolverSimFail();
            if (dConfig.callConfig.needsFulfillment()) {
                revert UserNotFulfilled(); // revert("ERR-E003 SolverFulfillmentFailure");
            }
            key = key.setAllSolversFailed();
        }

        if (dConfig.callConfig.needsPostOpsCall()) {
            key = key.holdDAppOperationLock(address(this));
            callSuccessful = _executePostOpsCall(auctionWon, returnData, executionEnvironment, key.pack());
            if (!callSuccessful) {
                if (key.isSimulation) revert PostOpsSimFail();
                else revert PostOpsFail();
            }
        }
        return (auctionWon, winningSearcherIndex);
    }

    function _solverExecutionIteration(
        DAppConfig calldata dConfig,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        bool auctionWon,
        address executionEnvironment,
        EscrowKey memory key
    )
        internal
        returns (bool, EscrowKey memory)
    {
        (auctionWon, key) = _executeSolverOperation(solverOp, dAppReturnData, executionEnvironment, key);
        unchecked {
            ++key.callIndex;
        }

        if (auctionWon) {
            _allocateValue(dConfig, solverOp.bidAmount, dAppReturnData, executionEnvironment, key.pack());
            key = key.allocationComplete();
        }
        return (auctionWon, key);
    }

    function _handleErrors(bytes4 errorSwitch, uint32 callConfig) internal view {
        if (msg.sender == SIMULATOR) {
            // Simulation
            if (errorSwitch == PreOpsSimFail.selector) {
                revert PreOpsSimFail();
            } else if (errorSwitch == UserOpSimFail.selector) {
                revert UserOpSimFail();
            } else if (errorSwitch == SolverSimFail.selector) {
                revert SolverSimFail();
            } else if (errorSwitch == PostOpsSimFail.selector) {
                revert PostOpsSimFail();
            }
        }
        if (errorSwitch == UserNotFulfilled.selector) {
            revert UserNotFulfilled();
        }
        if (callConfig.allowsReuseUserOps()) {
            assembly {
                mstore(0, errorSwitch)
                revert(0, 4)
            }
        }

        // Refund the msg.value to sender if it errored
        SafeTransferLib.safeTransferETH(msg.sender, msg.value);
    }

    function _verifyCallerIsExecutionEnv(address user, address controller, uint32 callConfig) internal view override {
        if (msg.sender != _getExecutionEnvironmentCustom(user, controller.codehash, controller, callConfig)) {
            revert EnvironmentMismatch();
        }
    }
}
