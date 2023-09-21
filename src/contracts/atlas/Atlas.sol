//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {Factory} from "./Factory.sol";

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";
import "../types/VerificationTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Atlas is Test, Factory {
    using CallVerification for UserCall;
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    constructor(uint32 _escrowDuration) Factory(_escrowDuration) {}

    function createExecutionEnvironment(DAppConfig calldata dConfig) external returns (address executionEnvironment) {
        executionEnvironment = _setExecutionEnvironment(dConfig, msg.sender, dConfig.to.codehash);
    }

    function metacall(
        DAppConfig calldata dConfig, // supplied by frontend
        UserOperation calldata userOp, // set by user
        SolverOperation[] calldata solverOps, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable {

        uint256 gasMarker = gasleft();

        // Verify that the calldata injection came from the dApp frontend
        // and that the signatures are valid. 
        bool valid = true;
        
        // Only verify signatures of meta txs if the original signer isn't the bundler
        // TODO: Consider extra reentrancy defense here?
        if (verification.proof.from != msg.sender && !_verifyDApp(userOp.call.to, dConfig, verification)) {
            valid = false;
        }
        
        if (userOp.call.from != msg.sender && !_verifyUser(dConfig, userOp)) { 
            valid = false; 
        }

        // TODO: Add optionality to bypass DAppControl signatures if user can fully bundle tx

        // Get the execution environment
        address executionEnvironment = _getExecutionEnvironmentCustom(userOp.call.from, verification.proof.controlCodeHash, dConfig.to, dConfig.callConfig);

        // Check that the value of the tx is greater than or equal to the value specified
        if (msg.value < userOp.call.value) { valid = false; }
        //if (msg.sender != tx.origin) { valid = false; }
        if (solverOps.length >= type(uint8).max - 1) { valid = false; }
        if (block.number > userOp.call.deadline || block.number > verification.proof.deadline) { valid = false; }
        if (tx.gasprice > userOp.call.maxFeePerGas) { valid = false; }
        if (executionEnvironment.codehash == bytes32(0)) { valid = false; }
        if (!dConfig.callConfig.allowsZeroSolvers() || dConfig.callConfig.needsSolverPostCall()) {
            if (solverOps.length == 0) { valid = false; }
        }
        // TODO: More checks 

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        if (!valid) {
            return;
        }

        // Initialize the lock
        _initializeEscrowLock(executionEnvironment);

        try this.execute{value: msg.value}(dConfig, userOp.call, solverOps, executionEnvironment, verification.proof.callChainHash) 
            returns (uint256 accruedGasRebate) {
            console.log("accruedGasRebate",accruedGasRebate);
            // Gas Refund to sender only if execution is successful
            _executeGasRefund(gasMarker, accruedGasRebate, userOp.call.from);

        } catch {
            // TODO: This portion needs more nuanced logic to prevent the replay of failed solver txs
            if (dConfig.callConfig.allowsReuseUserOps()) {
                revert("ERR-F07 RevertToReuse");
            }
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
        bytes32 callChainHash
    ) external payable returns (uint256 accruedGasRebate) {
        {
        // This is a self.call made externally so that it can be used with try/catch
        require(msg.sender == address(this), "ERR-F06 InvalidAccess");
        
        // verify the call sequence
        require(callChainHash == CallVerification.getCallChainHash(dConfig, uCall, solverOps), "ERR-F07 InvalidSequence");
        }
        // Begin execution
        accruedGasRebate = _execute(dConfig, uCall, solverOps, executionEnvironment);
    }

    function _execute(
        DAppConfig calldata dConfig,
        UserCall calldata uCall,
        SolverOperation[] calldata solverOps,
        address executionEnvironment
    ) internal returns (uint256 accruedGasRebate) {
        // Build the CallChainProof.  The penultimate hash will be used
        // to verify against the hash supplied by DAppControl
       
        bytes32 userOpHash = uCall.getUserOperationHash();

        uint32 callConfig = CallBits.buildCallConfig(uCall.control);

        // Initialize the locks
        EscrowKey memory key = _buildEscrowLock(dConfig, executionEnvironment, uint8(solverOps.length));

        bytes memory preOpsReturnData;
        if (dConfig.callConfig.needsPreOpsCall()) {
            key = key.holdPreOpsLock(dConfig.to);
            preOpsReturnData = _executePreOpsCall(uCall, executionEnvironment, key.pack());
        }

        key = key.holdUserLock(uCall.to);
        bytes memory userReturnData = _executeUserOperation(uCall, executionEnvironment, key.pack());

        bytes memory protocolReturnData;
        if (CallBits.needsPreOpsReturnData(callConfig)) {
            protocolReturnData = preOpsReturnData;
        }
        if (CallBits.needsUserReturnData(callConfig)) {
            protocolReturnData = bytes.concat(protocolReturnData, userReturnData);
        }

        bytes memory searcherReturnData;
        if(CallBits.forwardPreOpsReturnData(callConfig)) {
            searcherReturnData = preOpsReturnData;
        }
        if(CallBits.forwardUserReturnData(callConfig)) {
            searcherReturnData = bytes.concat(searcherReturnData, userReturnData);
        }

        bool auctionWon;

        for (; key.callIndex < key.callMax - 1;) {

            // Only execute solver meta tx if userOpHash matches 
            if (!auctionWon && userOpHash == solverOps[key.callIndex-2].call.userOpHash) {
                (auctionWon, key) = _solverExecutionIteration(
                        dConfig, solverOps[key.callIndex-2], protocolReturnData, searcherReturnData, auctionWon, executionEnvironment, key
                    );
            }

            unchecked {
                ++key.callIndex;
            }
        }

        // If no solver was successful, manually transition the lock
        if (!auctionWon) {
            if (dConfig.callConfig.needsSolverPostCall()) {
                revert("ERR-F08 UserNotFulfilled");
            }
            key = key.setAllSolversFailed();
        }

        if (dConfig.callConfig.needsPostOpsCall()) {
            key = key.holdVerificationLock(address(this));
            _executePostOpsCall(protocolReturnData, executionEnvironment, key.pack());
        }
        return uint256(key.gasRefund);
    }

    function _solverExecutionIteration(
        DAppConfig calldata dConfig,
        SolverOperation calldata solverOp,
        bytes memory protocolReturnData,
        bytes memory searcherReturnData,
        bool auctionWon,
        address executionEnvironment,
        EscrowKey memory key
    ) internal returns (bool, EscrowKey memory) {
        (auctionWon, key) = _executeSolverOperation(solverOp, protocolReturnData, searcherReturnData, executionEnvironment, key);
        if (auctionWon) {
            _allocateValue(dConfig, solverOp.bids, protocolReturnData, executionEnvironment, key.pack());
            key = key.allocationComplete();
        }
        return (auctionWon, key);
    }

    function testUserOperation(UserCall calldata uCall) external view returns (bool) {
        address control = uCall.control;
        uint32 callConfig = CallBits.buildCallConfig(control);
        return _testUserOperation(uCall, control, callConfig);
    }

    function testUserOperation(UserOperation calldata userOp) external view returns (bool) {
        if (userOp.to != address(this)) {return false;}
        address control = userOp.call.control;
        uint32 callConfig = CallBits.buildCallConfig(control);

        DAppConfig memory dConfig = DAppConfig(userOp.call.control, callConfig);

        return _validateUser(dConfig, userOp) && _testUserOperation(userOp.call, control, callConfig);
    }

    function _testUserOperation(UserCall calldata uCall, address control, uint32 callConfig) internal view returns (bool) {
        if (callConfig == 0) {
            return false;
        }

        address executionEnvironment = _getExecutionEnvironmentCustom(
            uCall.from, control.codehash, control, callConfig);

        if (executionEnvironment.codehash == bytes32(0) || control.codehash == bytes32(0)) {
            return false;
        } 
        return IExecutionEnvironment(executionEnvironment).validateUserOperation(uCall);
    }
}
