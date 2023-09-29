//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {Factory} from "./Factory.sol";
import {UserSimulationFailed, UserUnexpectedSuccess, UserSimulationSucceeded} from "../types/Emissions.sol";

import {FastLaneErrorsEvents} from "../types/Emissions.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/LockTypes.sol";
import "../types/DAppApprovalTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Atlas is Test, Factory {
    using CallVerification for UserCall;
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    constructor(uint32 _escrowDuration, address _simulator) Factory(_escrowDuration, _simulator) {}

    function createExecutionEnvironment(DAppConfig calldata dConfig) external returns (address executionEnvironment) {
        executionEnvironment = _setExecutionEnvironment(dConfig, msg.sender, dConfig.to.codehash);
    }

    function getExecutionEnvironment(address user, address dAppControl) external view returns (address executionEnvironment, uint32 callConfig, bool exists) {
        callConfig = CallBits.buildCallConfig(dAppControl);
        executionEnvironment = _getExecutionEnvironmentCustom(user, dAppControl.codehash, dAppControl, callConfig);
        exists = executionEnvironment.codehash != bytes32(0);
    }

    function metacall( // <- Entrypoint Function
        DAppConfig calldata dConfig, // supplied by frontend
        UserOperation calldata userOp, // set by user
        SolverOperation[] calldata solverOps, // supplied by FastLane via frontend integration
        DAppOperation calldata dAppOp // supplied by front end after it sees the other data
    ) external payable returns (bool auctionWon) {

        uint256 gasMarker = gasleft();

        // Get the execution environment
        address executionEnvironment = _getExecutionEnvironmentCustom(userOp.call.from, dAppOp.approval.controlCodeHash, userOp.call.control, dConfig.callConfig);

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        if (!_validCalls(dConfig, userOp, solverOps, dAppOp, executionEnvironment)) {
            if (msg.sender == simulator) {revert VerificationSimFail();} else { return false;}
        }

        // Initialize the lock
        _initializeEscrowLock(executionEnvironment);

        try this.execute{value: msg.value}(
            dConfig, userOp.call, solverOps, executionEnvironment, dAppOp.approval.callChainHash, msg.sender == simulator
        ) returns (bool _auctionWon, uint256 accruedGasRebate) {
            
            console.log("accruedGasRebate",accruedGasRebate);
            auctionWon = _auctionWon;
            // Gas Refund to sender only if execution is successful
            _executeGasRefund(gasMarker, accruedGasRebate, userOp.call.from);

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
        UserCall calldata uCall,
        SolverOperation[] calldata solverOps,
        address executionEnvironment,
        bytes32 callChainHash,
        bool isSimulation
    ) external payable returns (bool auctionWon, uint256 accruedGasRebate) {
        
        // This is a self.call made externally so that it can be used with try/catch
        require(msg.sender == address(this), "ERR-F06 InvalidAccess");
        
        // verify the call sequence
        require(
            callChainHash == CallVerification.getCallChainHash(dConfig, uCall, solverOps) || isSimulation, 
            "ERR-F07 InvalidSequence"
        );
        
        // Build the memory lock
        EscrowKey memory key = _buildEscrowLock(dConfig, executionEnvironment, uint8(solverOps.length), isSimulation);

        // Begin execution
        (auctionWon, accruedGasRebate) = _execute(dConfig, uCall, solverOps, executionEnvironment, key);
    }

    function _execute(
        DAppConfig calldata dConfig,
        UserCall calldata uCall,
        SolverOperation[] calldata solverOps,
        address executionEnvironment,
        EscrowKey memory key
    ) internal returns (bool auctionWon, uint256 accruedGasRebate) {
        // Build the CallChainProof.  The penultimate hash will be used
        // to verify against the hash supplied by DAppControl
       
        bool callSuccessful;
        bytes32 userOpHash = uCall.getUserOperationHash();

        uint32 callConfig = CallBits.buildCallConfig(uCall.control);

        bytes memory returnData;
        bytes memory searcherForwardData;

        if (dConfig.callConfig.needsPreOpsCall()) {
            key = key.holdPreOpsLock(dConfig.to);
            (callSuccessful, returnData) = _executePreOpsCall(uCall, executionEnvironment, key.pack());
            if (!callSuccessful) {
                if (key.isSimulation) { revert PreOpsSimFail(); } else { revert("ERR-E001 PreOpsFail"); }
            }
        }

        key = key.holdUserLock(uCall.to);
        
        bytes memory userReturnData;
        (callSuccessful, userReturnData) = _executeUserOperation(uCall, executionEnvironment, key.pack());
        if (!callSuccessful) {
            if (key.isSimulation) { revert UserOpSimFail(); } else { revert("ERR-E002 UserFail"); }
        }

        if (CallBits.needsPreOpsReturnData(callConfig)) {
            //returnData = returnData;
            if (CallBits.needsUserReturnData(callConfig)) {
                returnData = bytes.concat(returnData, userReturnData);
            }
        } else if (CallBits.needsUserReturnData(callConfig)) {
            returnData = userReturnData;
        } 
        
        if(CallBits.forwardReturnData(callConfig)) {
            searcherForwardData = returnData;
        }

        for (; key.callIndex < key.callMax - 1;) {

            // Only execute solver meta tx if userOpHash matches 
            if (!auctionWon && userOpHash == solverOps[key.callIndex-2].call.userOpHash) {
                (auctionWon, key) = _solverExecutionIteration(
                        dConfig, solverOps[key.callIndex-2], returnData, searcherForwardData, auctionWon, executionEnvironment, key
                    );
            }

            unchecked {
                ++key.callIndex;
            }
        }

        // If no solver was successful, manually transition the lock
        if (!auctionWon) {
            if (key.isSimulation) { revert SolverSimFail(); }
            if (dConfig.callConfig.needsSolverPostCall()) {
                revert UserNotFulfilled(); // revert("ERR-E003 SolverFulfillmentFailure");
            }
            key = key.setAllSolversFailed();
        }

        if (dConfig.callConfig.needsPostOpsCall()) {
            key = key.holdDAppOperationLock(address(this));
            callSuccessful = _executePostOpsCall(returnData, executionEnvironment, key.pack());
            if (!callSuccessful) {
                if (key.isSimulation) { revert PostOpsSimFail(); } else { revert("ERR-E005 PostOpsFail"); }
            }
        }
        return (auctionWon, uint256(key.gasRefund));
    }

    function _solverExecutionIteration(
        DAppConfig calldata dConfig,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        bytes memory searcherForwardData,
        bool auctionWon,
        address executionEnvironment,
        EscrowKey memory key
    ) internal returns (bool, EscrowKey memory) {
        (auctionWon, key) = _executeSolverOperation(solverOp, dAppReturnData, searcherForwardData, executionEnvironment, key);
        if (auctionWon) {
            _allocateValue(dConfig, solverOp.bids, dAppReturnData, executionEnvironment, key.pack());
            key = key.allocationComplete();
        }
        return (auctionWon, key);
    }

    function _validCalls(
        DAppConfig calldata dConfig, 
        UserOperation calldata userOp, 
        SolverOperation[] calldata solverOps, 
        DAppOperation calldata dAppOp,
        address executionEnvironment
    ) internal returns (bool) {
        // Verify that the calldata injection came from the dApp frontend
        // and that the signatures are valid. 
      
        bool isSimulation = msg.sender == simulator;

        // Some checks are only needed when call is not a simulation
        if (!isSimulation) {
            if (tx.gasprice > userOp.call.maxFeePerGas) {
                return false;
            }

            // Check that the value of the tx is greater than or equal to the value specified
            if (msg.value < userOp.call.value) { 
                return false;
            }
        }

        // Only verify signatures of meta txs if the original signer isn't the bundler
        // TODO: Consider extra reentrancy defense here?
        if (dAppOp.approval.from != msg.sender && !_verifyDApp(userOp.call.to, dConfig, dAppOp)) {
            bool bypass = isSimulation && dAppOp.signature.length == 0;
            if (!bypass) {
                return false;
            }
        }
        
        if (userOp.call.from != msg.sender && !_verifyUser(dConfig, userOp)) { 
            bool bypass = isSimulation && userOp.signature.length == 0;
            if (!bypass) {
                return false;   
            }
        }

        if (solverOps.length >= type(uint8).max - 1) {
            console.log("a");
            return false;
        }

        if (block.number > userOp.call.deadline) {
            bool bypass = isSimulation && userOp.call.deadline == 0;
            if (!bypass) {
                console.log("b");
                return false;
            }
        }

        if (block.number > dAppOp.approval.deadline) {
            bool bypass = isSimulation && dAppOp.approval.deadline == 0;
            if (!bypass) {
                console.log("c");
                return false;
            }
        }

        if (executionEnvironment.codehash == bytes32(0)) {
            console.log("d", executionEnvironment);
            return false;
        }

        if (!dConfig.callConfig.allowsZeroSolvers() || dConfig.callConfig.needsSolverPostCall()) {
            if (solverOps.length == 0) {
                console.log("e");
                return false;
            }
        }
        return true;
    }

    function _handleErrors(bytes4 errorSwitch, uint32 callConfig) internal view {
        if (msg.sender == simulator) { // Simulation
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
            revert("ERR-F07 RevertToReuse");
        }
    }
}
