//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {Factory} from "./Factory.sol";
import {UserSimulationFailed, UserUnexpectedSuccess, UserSimulationSucceeded} from "./Emissions.sol";

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";
import "../types/VerificationTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Atlas is Test, Factory {
    using CallVerification for UserMetaTx;
    using CallBits for uint16;
    using SafetyBits for EscrowKey;

    constructor(uint32 _escrowDuration) Factory(_escrowDuration) {}

    function createExecutionEnvironment(ProtocolCall calldata protocolCall) external returns (address executionEnvironment) {
        executionEnvironment = _setExecutionEnvironment(protocolCall, msg.sender, protocolCall.to.codehash);
    }

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) public payable returns (bool auctionWon) {

        uint256 gasMarker = gasleft();

        // Verify that the calldata injection came from the protocol frontend
        // and that the signatures are valid. 
        bool valid = true;
        
        // Only verify signatures of meta txs if the original signer isn't the bundler
        // TODO: Consider extra reentrancy defense here?
        if (verification.proof.from != msg.sender && !_verifyProtocol(userCall.metaTx.to, protocolCall, verification)) {
            valid = false;
        }
        
        if (userCall.metaTx.from != msg.sender && !_verifyUser(protocolCall, userCall)) { 
            valid = false; 
        }

        // TODO: Add optionality to bypass ProtocolControl signatures if user can fully bundle tx

        // Get the execution environment
        address executionEnvironment = _getExecutionEnvironmentCustom(userCall.metaTx.from, verification.proof.controlCodeHash, protocolCall.to, protocolCall.callConfig);

        // Check that the value of the tx is greater than or equal to the value specified
        if (msg.value < userCall.metaTx.value) { valid = false; }
        //if (msg.sender != tx.origin) { valid = false; }
        if (searcherCalls.length >= type(uint8).max - 1) { valid = false; }
        if (block.number > userCall.metaTx.deadline || block.number > verification.proof.deadline) { valid = false; }
        if (tx.gasprice > userCall.metaTx.maxFeePerGas) { valid = false; }
        if (executionEnvironment.codehash == bytes32(0)) { valid = false; }
        if (!protocolCall.callConfig.allowsZeroSearchers() || protocolCall.callConfig.needsSearcherPostCall()) {
            if (searcherCalls.length == 0) { valid = false; }
        }
        // TODO: More checks 

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        if (!valid) {
            return false;
        }

        // Initialize the lock
        _initializeEscrowLock(executionEnvironment);

        try this.execute{value: msg.value}(protocolCall, userCall.metaTx, searcherCalls, executionEnvironment, verification.proof.callChainHash) 
            returns (bool _auctionWon, uint256 accruedGasRebate) {
            console.log("accruedGasRebate",accruedGasRebate);
            auctionWon = _auctionWon;
            // Gas Refund to sender only if execution is successful
            _executeGasRefund(gasMarker, accruedGasRebate, userCall.metaTx.from);

        } catch {
            // TODO: This portion needs more nuanced logic to prevent the replay of failed searcher txs
            if (protocolCall.callConfig.allowsReuseUserOps()) {
                revert("ERR-F07 RevertToReuse");
            }
        }

        // Release the lock
        _releaseEscrowLock();

        console.log("total gas used", gasMarker - gasleft());
    }

    function execute(
        ProtocolCall calldata protocolCall,
        UserMetaTx calldata userMetaTx,
        SearcherCall[] calldata searcherCalls,
        address executionEnvironment,
        bytes32 callChainHash
    ) external payable returns (bool auctionWon, uint256 accruedGasRebate) {
        {
        // This is a self.call made externally so that it can be used with try/catch
        require(msg.sender == address(this), "ERR-F06 InvalidAccess");
        
        // verify the call sequence
        require(callChainHash == CallVerification.getCallChainHash(protocolCall, userMetaTx, searcherCalls), "ERR-F07 InvalidSequence");
        }
        // Begin execution
        (auctionWon, accruedGasRebate) = _execute(protocolCall, userMetaTx, searcherCalls, executionEnvironment);
    }

    function _execute(
        ProtocolCall calldata protocolCall,
        UserMetaTx calldata userMetaTx,
        SearcherCall[] calldata searcherCalls,
        address executionEnvironment
    ) internal returns (bool auctionWon, uint256 accruedGasRebate) {
        // Build the CallChainProof.  The penultimate hash will be used
        // to verify against the hash supplied by ProtocolControl
       
        bytes32 userCallHash = userMetaTx.getUserCallHash();

        uint16 callConfig = CallBits.buildCallConfig(userMetaTx.control);

        // Initialize the locks
        EscrowKey memory key = _buildEscrowLock(protocolCall, executionEnvironment, uint8(searcherCalls.length));

        bytes memory stagingReturnData;
        if (protocolCall.callConfig.needsStagingCall()) {
            key = key.holdStagingLock(protocolCall.to);
            stagingReturnData = _executeStagingCall(userMetaTx, executionEnvironment, key.pack());
        }

        key = key.holdUserLock(userMetaTx.to);
        bytes memory userReturnData = _executeUserCall(userMetaTx, executionEnvironment, key.pack());

        bytes memory returnData;
        if (CallBits.needsStagingReturnData(callConfig)) {
            returnData = stagingReturnData;
        }
        if (CallBits.needsUserReturnData(callConfig)) {
            returnData = bytes.concat(returnData, userReturnData);
        }

        for (; key.callIndex < key.callMax - 1;) {

            // Only execute searcher meta tx if userCallHash matches 
            if (!auctionWon && userCallHash == searcherCalls[key.callIndex-2].metaTx.userCallHash) {
                (auctionWon, key) = _searcherExecutionIteration(
                        protocolCall, searcherCalls[key.callIndex-2], returnData, auctionWon, executionEnvironment, key
                    );
            }

            unchecked {
                ++key.callIndex;
            }
        }

        // If no searcher was successful, manually transition the lock
        if (!auctionWon) {
            if (protocolCall.callConfig.needsSearcherPostCall()) {
                revert("ERR-F08 UserNotFulfilled");
            }
            key = key.setAllSearchersFailed();
        }

        if (protocolCall.callConfig.needsVerificationCall()) {
            key = key.holdVerificationLock(address(this));
            _executeVerificationCall(returnData, executionEnvironment, key.pack());
        }
        return (auctionWon, uint256(key.gasRefund));
    }

    function _searcherExecutionIteration(
        ProtocolCall calldata protocolCall,
        SearcherCall calldata searcherCall,
        bytes memory returnData,
        bool auctionWon,
        address executionEnvironment,
        EscrowKey memory key
    ) internal returns (bool, EscrowKey memory) {
        (auctionWon, key) = _executeSearcherCall(searcherCall, returnData, executionEnvironment, key);
        if (auctionWon) {
            _executePayments(protocolCall, searcherCall.bids, returnData, executionEnvironment, key.pack());
            key = key.allocationComplete();
        }
        return (auctionWon, key);
    }

    function testUserCall(UserMetaTx calldata userMetaTx) public returns (bool) {
        address control = userMetaTx.control;
        uint16 callConfig = CallBits.buildCallConfig(control);

        ProtocolCall memory protocolCall = ProtocolCall(userMetaTx.control, callConfig);

        /*
        // COMMENTED OUT FOR TESTS
        bool success;
        bytes memory data = abi.encodeWithSelector(
            this.testUserCallWrapper.selector, 
            protocolCall,
            userMetaTx
        );

        (success, data) = address(this).call{value: userMetaTx.value}(data);
        if (success) {
            revert UserUnexpectedSuccess();
        }

        bytes4 errorSwitch = bytes4(data);
        if (errorSwitch == UserSimulationSucceeded.selector) {
            return true;
        } else {
            return false;
        }
        */
        try this.testUserCallWrapper(protocolCall, userMetaTx) {
            revert UserUnexpectedSuccess();
        
        } catch (bytes memory data) {
            bytes4 errorSwitch = bytes4(data);
            if (errorSwitch == UserSimulationSucceeded.selector) {
                return true;
            } else {
                return false;
            }
        }
    }

    function testUserCall(UserCall calldata userCall) external returns (bool) {
        if (userCall.to != address(this)) {return false;}
        return testUserCall(userCall.metaTx);
    }

    function testUserCallWrapper(ProtocolCall calldata protocolCall, UserMetaTx calldata userMetaTx) external {
        require(msg.sender == address(this), "ERR-SIM001 MustCallSelf");

        if (protocolCall.callConfig == 0) {
            revert UserSimulationFailed();
        }

        address executionEnvironment = _getExecutionEnvironmentCustom(
            userMetaTx.from, protocolCall.to.codehash, protocolCall.to, protocolCall.callConfig);

        _initializeEscrowLock(executionEnvironment);

        if (executionEnvironment.codehash == bytes32(0) || protocolCall.to.codehash == bytes32(0)) {
            revert UserSimulationFailed();
        } 

        // Initialize the locks
        EscrowKey memory key = _buildEscrowLock(protocolCall, executionEnvironment, uint8(2));

        bytes memory stagingReturnData;
        if (protocolCall.callConfig.needsStagingCall()) {
            key = key.holdStagingLock(protocolCall.to);
            stagingReturnData = _executeStagingCall(userMetaTx, executionEnvironment, key.pack());
        }

        key = key.holdUserLock(userMetaTx.to);
        _executeUserCall(userMetaTx, executionEnvironment, key.pack());
        
        revert UserSimulationSucceeded();
    }

    function metacallSimulation(
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        SearcherCall[] calldata searcherCalls,
        Verification calldata verification
    ) external payable {
        if (!metacall(protocolCall, userCall, searcherCalls, verification)) {
            revert("ERR-S01 NoAuctionWinner");
        }
        revert("ERR-S00 SimulationPassed");
    }

    function testSearcherCalls(
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        SearcherCall[] calldata searcherCalls,
        Verification calldata verification
    ) external payable returns (bool auctionWon) {
        try this.metacallSimulation{value: msg.value}(protocolCall, userCall, searcherCalls, verification) {}
        catch (bytes memory revertData) {
            for (uint256 i; i < revertData.length-4;) {
                revertData[i] = revertData[i+4];
                unchecked{ ++i; }
            }
            bytes32 revertMsg = keccak256(abi.decode(revertData, (bytes)));

            if (
                revertMsg == keccak256(abi.encodePacked("ERR-S01 NoAuctionWinner"))
                    || revertMsg == keccak256(abi.encodePacked("ERR-F08 UserNotFulfilled"))
            ) {
                auctionWon = false;
            } else {
                auctionWon = true;
            }
        }
    }
}
