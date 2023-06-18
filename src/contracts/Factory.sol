//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { FastLaneDataTypes } from "./DataTypes.sol";
import { ThogLock } from "./ThogLock.sol";

import { FastLaneEscrow } from "./SearcherEscrow.sol";
import { FastLaneProtoHandler } from "./Handler.sol";


contract FastLaneFactory is ThogLock {

    uint32 immutable public escrowDuration;
    address immutable public fastLanePayee;
    address immutable public escrowAddress; 

    uint256 internal _keyCode;

    FastLaneEscrow internal _escrowContract = new FastLaneEscrow();

    constructor(
            address _fastlanePayee, 
            uint256 _protocolShare,
            uint32 _escrowDuration

    ) ThogLock(address(escrowContract), address(this)) {

        fastLanePayee = _fastlanePayee;
        protocolShare = _protocolShare;
        escrowDuration = _escrowDuration;
        escrowAddress = address(_escrowContract);
    }

    function metacall(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable {

        require(!_baseLock, "ERR-F01 FactoryLock");

        ProtocolData memory protocolData = _protocolData[userCall.to];

        require(protocolData.owner != address(0), "ERR-00 UnsuportedUserTo");

        Lock memory mLock = _thogLock(
            protocolData.nonce,
            _getHandlerAddress(protocolData),
            searcherCalls
        );

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

        _handler.protoCall(
            mLock,
            stagingCall,
            userCall,
            payeeData,
            searcherCalls
        );

    }

    function _getHandlerAddress(
        ProtocolData memory protocolData
    ) internal returns (address handlerAddress) {
        
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

    function prepOuterLock(uint256 keyCode) external {
        // address(this) == _factory
        require(msg.sender == _escrowAddress, "ERR-T03 InvalidCaller");
        require(_keyCode == 0);
        
        _keyCode = keyCode;

        _baseLock = BaseLock.Pending;
    }

}