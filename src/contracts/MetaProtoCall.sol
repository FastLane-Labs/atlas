//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IMetaProtoCall } from "../interfaces/IMetaProtoCall.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { Escrow } from "./Escrow.sol";
import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";
import { ProtocolVerifier } from "./ProtocolVerification.sol";

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall,
    ProtocolData,
    Verification
} from "../libraries/DataTypes.sol";

contract MetaProtoCall is ProtocolVerifier, ReentrancyGuard {

    uint32 immutable public escrowDuration;
    address immutable public fastLanePayee;
    address immutable public escrowAddress;

    // map to load execution environment parameters for each protocol
    mapping(address => ProtocolData) public protocolDataMap;

    FastLaneEscrow internal _escrowContract = new FastLaneEscrow(uint32(64));

    constructor(
            address _fastlanePayee,
            uint32 _escrowDuration

    ) {
        fastLanePayee = _fastlanePayee;
        escrowDuration = _escrowDuration;
        escrowAddress = address(_escrowContract);
    }

    function metacall(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable nonReentrant {

        // Load protocol data for the user's targeted protocol
        ProtocolData memory protocolData = protocolDataMap[userCall.to];

        // Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        if (!_verifyProtocol(verification, protocolData)) {
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
                    escrowAddress,
                    protocolData.owner,
                    protocolData.callConfig,
                    protocolData.split
                )
            )
        }(protocolData.split, escrowAddress);

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

    function _getHandlerAddress(
        ProtocolData memory protocolData
    ) internal view returns (address handlerAddress) {
        
        bytes32 salt = keccak256(
            abi.encodePacked(
                escrowAddress,
                protocolData.owner,
                protocolData.callConfig,
                protocolData.split
            )
        );

        handlerAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(
                abi.encodePacked(
                    type(ExecutionEnvironment).creationCode,
                    protocolData.split,
                    escrowAddress
                )
            )
        ))))); // this line causes me immeasurable pain
    }
}