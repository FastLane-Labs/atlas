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

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable {

        uint256 gasMarker = gasleft();

        // Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert.
        // This allows signature data to be stored, which helps prevent
        // replay attacks.
        if (!_verifyProtocol(userCall.to, protocolCall, verification)) {
            return;
        }

        // TODO: Make sure all searcher nonces are incremented on fail. 

        // Check that the value of the tx is greater than or equal to the value specified
        // NOTE: a msg.value *higher* than user value could be used by the staging call.
        // There is a further check in the handler before the usercall to verify.
        require(msg.value >= userCall.value, "ERR-H03 ValueExceedsBalance");
        require(searcherCalls.length < type(uint8).max - 1, "ERR-F02 TooManySearcherCalls");
        require(
            block.number <= userCall.deadline && block.number <= verification.proof.deadline, "ERR-F03 DeadlineExceeded"
        );

        console.log("initial verification gas cost", gasMarker - gasleft());

        gasMarker = gasleft();

        // Get the execution environment
        address environment = _setExecutionEnvironment(protocolCall, userCall.from, verification.proof.controlCodeHash);

        console.log("contract creation gas cost", gasMarker - gasleft());

        gasMarker = gasleft();

        // Initialize the locks
        _initializeEscrowLocks(protocolCall, environment, uint8(searcherCalls.length));

        // Begin execution
        bytes32 callChainHashHead = _execute(protocolCall, userCall, searcherCalls, environment);

        // Verify that the meta transactions were executed in the correct sequence
        require(callChainHashHead == verification.proof.callChainHash, "ERR-F05 InvalidCallChain");

        // Gas Refund to sender
        _executeGasRefund(msg.sender);

        // Release the lock
        _releaseEscrowLocks();

        console.log("ex contract creation gas cost", gasMarker - gasleft());
    }

    function _execute(
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
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
        bool auctionAlreadyWon;

        for (; i < searcherCalls.length;) {

            proof = proof.next(searcherCalls[i].metaTx.from, searcherCalls[i].metaTx.data);

            // Only execute searcher meta tx if userCallHash matches 
            if (userCallHash == searcherCalls[i].metaTx.userCallHash) {
                auctionAlreadyWon = auctionAlreadyWon
                    || _searcherExecutionIteration(
                        protocolCall, searcherCalls[i], auctionAlreadyWon, environment
                    );
            }

            unchecked {
                ++i;
            }
        }

        // If no searcher was successful, manually transition the lock
        if (!auctionAlreadyWon) {
            _notMadJustDisappointed();
        }

        _executeVerificationCall(protocolCall, stagingReturnData, userReturnData, environment);
        
        return proof.targetHash;
    }

    function _searcherExecutionIteration(
        ProtocolCall calldata protocolCall,
        SearcherCall calldata searcherCall,
        bool auctionAlreadyWon,
        address environment
    ) internal returns (bool) {
        if (_executeSearcherCall(searcherCall, auctionAlreadyWon, environment)) {
            if (!auctionAlreadyWon) {
                auctionAlreadyWon = true;
                _executePayments(protocolCall, searcherCall.bids, environment);
            }
        }
        return auctionAlreadyWon;
    }
}
