//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

abstract contract Metacall is ReentrancyGuard {

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable nonReentrant {
        // build a memory array to later verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index.
        bytes32[] memory executionHashChain = CallVerification.buildExecutionHashChain(
            protocolCall,
            userCall,
            searcherCalls
        );

        // Get the execution environment
        address environment = _prepEnvironment(protocolCall);

        // Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        if (!_validateProtocolControl(environment, userCall.to, searcherCalls.length, protocolCall, verification)) {
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
        require(block.number <= userCall.deadline, "ERR-F03 DeadlineExceeded");

        // Handoff to the execution environment, which returns the verified proof
        CallChainProof memory proof = _execute(
            environment,
            protocolCall,
            userCall,
            payeeData,
            searcherCalls,
            executionHashChain
        );

        // Verify that the execution system's sequencing of the transaction calldata was unaltered by searchers
        // NOTE: This functions as an "exploit prevention mechanism" as the contract itself already verifies 
        // trustless execution. 
        require(
            proof.previousHash == verification.proof.callChainHash, "ERR-F05 SearcherExploitDetected"
        );

        // Release the lock
        _releaseLock(proof.previousHash, protocolCall);
    }

    // VIRTUAL FUNCTIONS
    function _validateProtocolControl(
        address environment,
        address userCallTo,
        uint256 searcherCallsLength,
        ProtocolCall calldata protocolCall,
        Verification calldata verification
    ) internal virtual returns (bool);

    function _prepEnvironment(ProtocolCall calldata protocolCall) internal virtual returns (address environment);

    function _execute(
        address environment,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, 
        SearcherCall[] calldata searcherCalls, 
        bytes32[] memory executionHashChain 
    ) internal virtual returns (CallChainProof memory);

    function _releaseLock(bytes32 key, ProtocolCall calldata protocolCall) internal virtual;
}