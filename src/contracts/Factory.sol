//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IFactory } from "../interfaces/IFactory.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { FastLaneDataTypes } from "./DataTypes.sol";
import { ThogLock } from "./ThogLock.sol";

import { FastLaneEscrow } from "./SearcherEscrow.sol";
import { FastLaneProtoHandler } from "./Handler.sol";


contract FastLaneFactory is IFactory, ThogLock {

    uint32 immutable public escrowDuration;
    address immutable public fastLanePayee;
    address immutable public escrowAddress;

    FastLaneEscrow internal _escrowContract = new FastLaneEscrow(uint32(64));

    constructor(
            address _fastlanePayee,
            uint32 _escrowDuration

    ) ThogLock(address(_escrowContract), address(this)) {

        fastLanePayee = _fastlanePayee;
        escrowDuration = _escrowDuration;
        escrowAddress = address(_escrowContract);
    }

    function metacall(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable {

        require(_baseLock == BaseLock.Unlocked, "ERR-F00 FactoryLock");

        ProtocolData memory protocolData = _protocolData[userCall.to];

        require(protocolData.owner != address(0), "ERR-F01 UnsuportedUserTo");

        // NOTE: This is expected to revert if there's already a contract at that location
        FastLaneProtoHandler _handler = new FastLaneProtoHandler{
            salt: keccak256(
                abi.encodePacked(
                    escrowAddress,
                    protocolData.owner,
                    protocolData.callConfig,
                    protocolData.split
                )
            )
        }(protocolData.split, escrowAddress);

        uint256 lockCode = _initThogLock(
            address(_handler),
            userCall,
            searcherCalls
        );

        _handler.protoCall(
            stagingCall,
            userCall,
            payeeData,
            searcherCalls
        );

        require(
            (_baseLock == BaseLock.Pending) && (lockCode == _keyCode),
            "ERR-F02 Error Unlocking"
        );

        // _baseLock = BaseLock.Unlocked;
        delete _baseLock;
        delete _keyCode;
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
            keccak256(abi.encodePacked(
                type(FastLaneProtoHandler).creationCode,
                protocolData.split,
                escrowAddress
            ))
        )))));
    }

    function initReleaseFactoryThogLock(uint256 keyCode) external {
        // address(this) == _factory
        require(msg.sender == _escrowAddress, "ERR-F20 InvalidCaller");
        require(_keyCode == 0, "ERR-F21 KeyTampering");
        require(_baseLock == BaseLock.Locked, "ERR-F22 NotLocked");

        _keyCode = keyCode;
        _baseLock = BaseLock.Pending;
    }

}