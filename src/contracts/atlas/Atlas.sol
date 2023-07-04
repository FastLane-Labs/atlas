//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Factory } from "./Factory.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract Atlas is Test, Factory {
    using CallVerification for CallChainProof;
    using CallVerification for bytes32[];

    constructor(
        uint32 _escrowDuration
    ) Factory(_escrowDuration) {}

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable {
        // Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        if (!_verifyProtocol(userCall.to, protocolCall, verification)) {
            return;
        }

        require(
            keccak256(abi.encode(payeeData)) == verification.proof.payeeHash,
            "ERR-H02 PayeeMismatch"
        );
        
        // Check that the value of the tx is greater than or equal to the value specified
        // NOTE: a msg.value *higher* than user value could be used by the staging call.
        // There is a further check in the handler before the usercall to verify. 
        require(msg.value >= userCall.value, "ERR-H03 ValueExceedsBalance");
        require(searcherCalls.length < type(uint8).max -1, "ERR-F02 TooManySearcherCalls");
        require(
            block.number <= userCall.deadline && block.number <= verification.proof.deadline,
            "ERR-F03 DeadlineExceeded"
        );

        uint256 gasMarker = gasleft();
        // Get the execution environment
        address environment = _prepEnvironment(protocolCall);
        console.log("contract creation gas cost",gasMarker - gasleft());

        gasMarker = gasleft();

        // Initialize the locks
        _initializeEscrowLocks(environment, uint8(searcherCalls.length));

        // Begin execution
        bytes32 callChainHash = _execute(
            protocolCall,
            userCall,
            payeeData,
            searcherCalls,
            environment
        );

        require(callChainHash == verification.proof.callChainHash, "ERR-F05 InvalidCallChain");

        // Release the lock
        _releaseEscrowLocks();

        console.log("remaining call gas cost",gasMarker - gasleft());
    }


    function _prepEnvironment(ProtocolCall calldata protocolCall) internal returns (address environment) {
        // Calculate the user's execution environment address
        environment = _getExecutionEnvironment(msg.sender, protocolCall.to);

        // Initialize a new, blank execution environment for the user if there isn't one already
        if (environment.codehash == bytes32(0)) {
            environment = _deployExecutionEnvironment(
                msg.sender,
                protocolCall
            );
        }
    }

    function _execute(
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, 
        SearcherCall[] calldata searcherCalls,
        address environment
    ) internal returns (bytes32 callChainHash) {
        // build a memory array to later verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index.
        bytes32[] memory executionHashChain = CallVerification.buildExecutionHashChain(
            protocolCall,
            userCall,
            searcherCalls
        );

        CallChainProof memory proof = CallVerification.initializeProof(
            userCall, executionHashChain[0]
        );

        bytes memory stagingReturnData = _executeStagingCall(
            protocolCall, userCall, proof, environment
        );

        proof = proof.next(executionHashChain[1]);

        bytes memory userReturnData = _executeUserCall(
            protocolCall, userCall, proof, environment
        );

        proof = proof.next(executionHashChain[2]);

        uint256 i; 
        bool auctionAlreadyWon;
        for (; i < searcherCalls.length;) {

            auctionAlreadyWon = _searcherExecutionIteration(
                protocolCall, payeeData, searcherCalls[i], proof, auctionAlreadyWon, environment
            );
            proof = proof.next(executionHashChain[3+i]);
            unchecked { ++i; }
        }

        callChainHash = proof.previousHash; // Set the return Value 

        proof = proof.addVerificationCallProof(
            protocolCall.to,
            stagingReturnData,
            userReturnData
        );

        _executeUserRefund(userCall.from, environment);

        _executeVerificationCall(
            protocolCall, proof, stagingReturnData, userReturnData, environment
        );
    }

    function _searcherExecutionIteration(
        ProtocolCall calldata protocolCall,
        PayeeData[] calldata payeeData, 
        SearcherCall calldata searcherCall,
        CallChainProof memory proof,
        bool auctionAlreadyWon,
        address environment
    ) internal returns (bool) {
        if (_executeSearcherCall(
            searcherCall, proof, auctionAlreadyWon, environment
        )) {
            if (!auctionAlreadyWon) {
                auctionAlreadyWon = true;
                _executePayments(
                    protocolCall, searcherCall.bids, payeeData, environment
                );
            }
        }
        return auctionAlreadyWon;
    }
}