//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { Escrow } from "./Escrow.sol";
import { Factory } from "./Factory.sol";
import { ProtocolVerifier } from "./ProtocolVerification.sol";

import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";
import { SketchyStorageEnvironment } from "./SketchyStorage.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall,
    ProtocolData,
    Verification
} from "../libraries/DataTypes.sol";

contract Atlas is Factory, ProtocolVerifier {

    bytes32 internal _dirtyLock;

    constructor(
        address _fastlanePayee,
        uint32 _escrowDuration
    ) Factory(_fastlanePayee, _escrowDuration) {}

    function metacall(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable nonReentrant {

        // Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        (bool invalidCall, ProtocolData memory protocolData) = _verifyProtocol(
            verification, userCall.to
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

        // handoff to the execution environment, which returns the verified
        // userCallHash and the final hash of the searcher chain. 
        (bytes32 userCallHash, bytes32 searcherChainHash) = _executionEnvironment.protoCall(
            stagingCall,
            userCall,
            payeeData,
            searcherCalls
        );

        // Verify that the frontend's view of the user's calldata is unaltered - presumably by user
        require(
            userCallHash == verification.proof.userCallHash, "ERR-F04 UserCallAltered"
        );

        // Verify that the frontend's view of the searchers' signed calldata was unaltered by user
        require(
            searcherChainHash == verification.proof.searcherChainHash, "ERR-F05 SearcherCallAltered"
        );

        // release the locks
        _escrowContract.releaseEscrowLocks();
    }

    function untrustedVerifyProtocol(
        address userCallTo,
        Verification calldata verification
    ) external nonReentrant returns (bool invalidCall, ProtocolData memory protocolData) {

        require(msg.sender == DIRTY_ADDRESS, "ERR-H03 InvalidCaller");
        
        (invalidCall, protocolData) = _verifyProtocol(userCallTo, verification);

        if (invalidCall) {
            return (invalidCall, protocolData);
        }

        // Initialize the escrow locks
        _escrowContract.initializeEscrowLocks(
            address(DIRTY_ADDRESS),
            uint8(searcherCalls.length)
        );

        _dirtyLock = keccak256(
            verification.proof.userCallHash,
            verification.proof.protocolDataHash,
            verification.proof.searcherChainHash
        );
    }

    function untrustedReleaseLock(bytes32 key) external nonReentrant {
        require(key == _dirtyLock && key != bytes32(0), "ERR-H04 IncorrectKey");
        
        delete _dirtyLock;

        _escrowContract.releaseEscrowLocks();
    }
}