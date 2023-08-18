//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Factory} from "./Factory.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

contract Atlas is Test, Factory {
    using CallVerification for CallChainProof;
    using CallVerification for bytes32[];
    using CallBits for uint16;

    constructor(uint32 _escrowDuration) Factory(_escrowDuration) {}

    function createExecutionEnvironment(ProtocolCall calldata protocolCall) external returns (address environment) {
        environment = _setExecutionEnvironment(protocolCall, msg.sender, protocolCall.to.codehash);
        //if (userNonces[msg.sender] == 0) {
        //    unchecked{ ++userNonces[msg.sender];}
        //}
    }

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable {

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
        address environment = _getExecutionEnvironmentCustom(userCall.metaTx.from, verification.proof.controlCodeHash, protocolCall.to, protocolCall.callConfig);

        // Check that the value of the tx is greater than or equal to the value specified
        if (msg.value < userCall.metaTx.value) { valid = false; }
        //if (msg.sender != tx.origin) { valid = false; }
        if (searcherCalls.length >= type(uint8).max - 1) { valid = false; }
        if (block.number > userCall.metaTx.deadline || block.number > verification.proof.deadline) { valid = false; }
        if (tx.gasprice > userCall.metaTx.maxFeePerGas) { valid = false; }
        if (environment.codehash == bytes32(0)) { valid = false; }
        if (!protocolCall.callConfig.allowsZeroSearchers() || protocolCall.callConfig.needsSearcherFullfillment()) {
            if (searcherCalls.length == 0) { valid = false; }
        }
        // TODO: More checks 

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        if (!valid) {
            return;
        }

        try this.execute{value: msg.value}(protocolCall, userCall.metaTx, searcherCalls, environment, verification.proof.callChainHash) 
            returns (uint256 accruedGasRebate) {
            // Gas Refund to sender only if execution is successful
            _executeGasRefund(gasMarker, accruedGasRebate, userCall.metaTx.from);

        } catch {
            // TODO: This portion needs more nuanced logic
            if (protocolCall.callConfig.allowsReuseUserOps()) {
                revert("ERR-F07 RevertToReuse");
            }
        }

        console.log("total gas used", gasMarker - gasleft());
    }

    function execute(
        ProtocolCall calldata protocolCall,
        UserMetaTx calldata userCall,
        SearcherCall[] calldata searcherCalls,
        address environment,
        bytes32 callChainHash
    ) external payable returns (uint256 accruedGasRebate) {
        // This is a self.call made externally so that it can be used with try/catch
        require(msg.sender == address(this), "ERR-F06 InvalidAccess");

        // Initialize the locks
        _initializeEscrowLocks(protocolCall, environment, uint8(searcherCalls.length));

        // Begin execution
        bytes32 callChainHashHead = _execute(protocolCall, userCall, searcherCalls, environment);

        // Verify that the meta transactions were executed in the correct sequence
        require(callChainHashHead == callChainHash, "ERR-F05 InvalidCallChain");

        accruedGasRebate = _getAccruedGasRebate();

        // Release the lock
        _releaseEscrowLocks();
    }

    function _execute(
        ProtocolCall calldata protocolCall,
        UserMetaTx calldata userCall,
        SearcherCall[] calldata searcherCalls,
        address environment
    ) internal returns (bytes32) {
        // Build the CallChainProof.  The penultimate hash will be used
        // to verify against the hash supplied by ProtocolControl
        CallChainProof memory proof = CallVerification.initializeProof(protocolCall, userCall);
        bytes32 userCallHash = keccak256(abi.encodePacked(userCall.to, userCall.data));

        bytes memory stagingReturnData = _executeStagingCall(protocolCall, userCall, environment);

        proof = proof.next(userCall.from, userCall.data);

        bytes memory userReturnData = _executeUserCall(userCall, environment);

        uint256 i;
        bool auctionWon;

        for (; i < searcherCalls.length;) {

            proof = proof.next(searcherCalls[i].metaTx.from, searcherCalls[i].metaTx.data);

            // Only execute searcher meta tx if userCallHash matches 
            if (userCallHash == searcherCalls[i].metaTx.userCallHash) {
                if (!auctionWon && _searcherExecutionIteration(
                        protocolCall, searcherCalls[i], stagingReturnData, auctionWon, environment
                    )) {
                        auctionWon = true;
                    }
            }

            unchecked {
                ++i;
            }
        }

        // If no searcher was successful, manually transition the lock
        if (!auctionWon) {
            if (protocolCall.callConfig.needsSearcherFullfillment()) {
                revert("ERR-F08 UserNotFulfilled");
            }
            _notMadJustDisappointed();
        }

        _executeVerificationCall(protocolCall, stagingReturnData, userReturnData, environment);
        
        return proof.targetHash;
    }

    function _searcherExecutionIteration(
        ProtocolCall calldata protocolCall,
        SearcherCall calldata searcherCall,
        bytes memory stagingReturnData,
        bool auctionAlreadyWon,
        address environment
    ) internal returns (bool) {
        if (_executeSearcherCall(searcherCall, stagingReturnData, auctionAlreadyWon, environment)) {
            if (!auctionAlreadyWon) {
                auctionAlreadyWon = true;
                _executePayments(protocolCall, searcherCall.bids, environment);
            }
        }
        return auctionAlreadyWon;
    }
}
