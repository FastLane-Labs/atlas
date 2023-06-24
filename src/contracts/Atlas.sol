//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { Escrow } from "./Escrow.sol";
import { FastLaneFactory } from "./Factory.sol";
import { ProtocolVerifier } from "./ProtocolVerification.sol";

import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";
import { SketchyStorageEnvironment } from "./SketchyStorage.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import {
    ProtocolCall,
    UserCall,
    PayeeData,
    SearcherCall,
    ProtocolData,
    Verification,
    CallChainProof
} from "../libraries/DataTypes.sol";

contract Atlas is FastLaneFactory, ProtocolVerifier {

    bytes32 internal _dirtyLock;

    constructor(
        address _fastlanePayee,
        uint32 _escrowDuration
    ) FastLaneFactory(_fastlanePayee, _escrowDuration) {}

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable nonReentrant {
        // build a memory array to later verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index
        // order is:
        //      0: stagingCall
        //      1: userCall + keccak of prior
        //      2 to n: searcherCalls + keccak of prior
        // NOTE: if the staging call is skipped, the userCall has the 0 index.
        bytes32[] memory executionHashChain = CallVerification.buildExecutionHashChain(
            protocolCall,
            userCall,
            searcherCalls
        );

        // Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        (bool invalidCall, ProtocolData memory protocolData) = _verifyProtocol(
            userCall.to, verification
        );
        if (!invalidCall) {
            return;
        }
        // Signature / hashing failures past this point can be safely reverted.
        // This is because those reverts are caused by invalid signatures or 
        // altered calldata, both of which are keys in the protocol's signature
        // and which will *always* fail, making replay attacks impossible. 

        // Check that the value of the tx is greater than or equal to the value specified
        // NOTE: a msg.value *higher* than user value could be used by the staging call.
        // There is a further check in the handler before the usercall to verify. 
        require(msg.value >= userCall.value, "ERR-H03 ValueExceedsBalance");
        require(protocolData.owner != address(0), "ERR-F01 UnsuportedUserTo");
        require(searcherCalls.length < type(uint8).max -1, "ERR-F02 TooManySearcherCalls");
        require(block.number <= userCall.deadline, "ERR-F03 DeadlineExceeded");

        // Initialize a new, blank execution environment
        // NOTE: This is expected to revert if there's already a contract at that location
        ExecutionEnvironment _executionEnvironment = new ExecutionEnvironment{
            salt: keccak256(
                abi.encodePacked(
                    block.chainid,
                    escrowAddress,
                    protocolData.owner,
                    protocolData.callConfig,
                    protocolData.split
                )
            )
        }(false, protocolData.split, escrowAddress);

        // Initialize the escrow locks
        _escrowContract.initializeEscrowLocks(
            address(_executionEnvironment),
            uint8(searcherCalls.length)
        );

        // Handoff to the execution environment, which returns the verified proof
        CallChainProof memory proof = _executionEnvironment.protoCall(
            protocolCall,
            userCall,
            payeeData,
            searcherCalls,
            executionHashChain
        );

        // Verify that the frontend's view of the searchers' signed calldata was unaltered by user
        require(
            executionHashChain[executionHashChain.length-2] == verification.proof.callChainHash, 
            "ERR-F05 UserCallAltered"
        );

        // Verify that the execution system's sequencing of the transaction calldata was unaltered by searchers
        // NOTE: This functions as an "exploit prevention mechanism" as the contract itself already verifies 
        // trustless execution. 
        require(
            proof.previousHash == verification.proof.callChainHash, "ERR-F05 SearcherExploitDetected"
        );

        // release the locks
        _escrowContract.releaseEscrowLocks();
    }

    function untrustedVerifyProtocol(
        address userCallTo,
        uint256 searcherCallsLength,
        Verification calldata verification
    ) external nonReentrant returns (bool invalidCall, ProtocolData memory protocolData) {

        require(msg.sender == dirtyAddress, "ERR-H03 InvalidCaller");
        require(_dirtyLock == bytes32(0), "ERR-H04 AlreadyLocked");
        
        (invalidCall, protocolData) = _verifyProtocol(userCallTo, verification);

        if (invalidCall) {
            return (invalidCall, protocolData);
        }

        // Initialize the escrow locks
        _escrowContract.initializeEscrowLocks(
            address(dirtyAddress),
            uint8(searcherCallsLength)
        );

        // Store the penultimate call hash
        _dirtyLock = verification.proof.callChainHash;
    }

    function untrustedReleaseLock(bytes32 key) external nonReentrant {
        require(key == _dirtyLock && key != bytes32(0), "ERR-H05 IncorrectKey");
        
        delete _dirtyLock;

        _escrowContract.releaseEscrowLocks();
    }
}