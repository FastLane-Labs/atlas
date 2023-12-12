//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IAtlasFactory } from "../interfaces/IAtlasFactory.sol";
import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";

import { Escrow } from "./Escrow.sol";

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

contract Atlas is Escrow {
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _boAtlETH,
        address _simulator
    )
        Escrow(_escrowDuration, _factory, _verification, _boAtlETH, _simulator)
    { }

    function createExecutionEnvironment(address dAppControl) external returns (address executionEnvironment) {
        executionEnvironment = IAtlasFactory(FACTORY).createExecutionEnvironment(msg.sender, dAppControl);
        IAtlasVerification(VERIFICATION).initializeNonce(msg.sender);
    }

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

        // TODO: Combine this w/ call to get executionEnvironment
        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);

        // Get the execution environment
        address executionEnvironment = IAtlasFactory(FACTORY).getExecutionEnvironmentCustom(
            userOp.from, dAppOp.control.codehash, userOp.control, dConfig.callConfig
        );

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        // NOTE: Currently reverting instead of graceful return to help w/ testing.
        ValidCallsResult validCallsResult;
        (solverOps, validCallsResult) = IAtlasVerification(VERIFICATION).validCalls(
            dConfig, userOp, solverOps, dAppOp, executionEnvironment, msg.value, msg.sender, msg.sender == SIMULATOR
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
        (auctionWon, winningSearcherIndex) = _execute(dConfig, userOp, solverOps, executionEnvironment, bundler, key);
    }

    function _execute(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        address executionEnvironment,
        address bundler,
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
            // Only execute solver meta tx if userOpHash matches
            if (!auctionWon && solverOps[winningSearcherIndex].from != address(0)) {
                (auctionWon, key) = _solverExecutionIteration(
                    dConfig, solverOps[winningSearcherIndex], returnData, auctionWon, executionEnvironment, bundler, key
                );
                if (auctionWon) break;
            }

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
            callSuccessful = _executePostOpsCall(returnData, executionEnvironment, key.pack());
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
        address bundler,
        EscrowKey memory key
    )
        internal
        returns (bool, EscrowKey memory)
    {
        (auctionWon, key) = _executeSolverOperation(solverOp, dAppReturnData, executionEnvironment, bundler, key);
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
            revert RevertToReuse();
        }
    }

    function _verifyCallerIsExecutionEnv(address user, address controller, uint32 callConfig) internal view override {
        if (
            msg.sender
                != IAtlasFactory(FACTORY).getExecutionEnvironmentCustom(user, controller.codehash, controller, callConfig)
        ) {
            revert EnvironmentMismatch();
        }
    }
}
