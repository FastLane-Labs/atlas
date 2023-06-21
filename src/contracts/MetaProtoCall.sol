//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IMetaProtoCall } from "../interfaces/IMetaProtoCall.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { FastLaneEscrow } from "./SearcherEscrow.sol";
import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall,
    ProtocolData
} from "../libraries/DataTypes.sol";

contract MetaProtoCall is ReentrancyGuard {

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
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable nonReentrant {

        // Check that the value of the tx is greater than or equal to the value specified
        // NOTE: a msg.value *higher* than user value could be used by the staging call.
        // There is a further check in the handler before the usercall to verify. 
        require(msg.value >= userCall.value, "ERR-H03 ValueExceedsBalance");

        ProtocolData memory protocolData = protocolDataMap[userCall.to];

        require(protocolData.owner != address(0), "ERR-F01 UnsuportedUserTo");
        require(searcherCalls.length < type(uint8).max -1, "ERR-F02 TooManySearcherCalls");

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

        // handoff to the execution environment
        _executionEnvironment.protoCall{value: msg.value}(
            stagingCall,
            userCall,
            payeeData,
            searcherCalls
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