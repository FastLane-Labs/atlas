//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { Escrow } from "./Escrow.sol";
import { SketchyStorageEnvironment } from "./SketchyStorage.sol";
import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";

import {
    ProtocolData
} from "../libraries/DataTypes.sol";

contract FastLaneFactory is Ownable, ReentrancyGuard {

    uint256 constant public PROTOCOL_SHARE = 5;

    uint32 immutable public escrowDuration;
    address immutable public fastLanePayee;

    Escrow internal _escrowContract = new Escrow(uint32(64));

    address immutable public escrowAddress;

    bytes32 immutable internal _dirtySalt;

    address immutable public dirtyAddress;

    constructor(
            address _fastlanePayee,
            uint32 _escrowDuration

    ) {
        fastLanePayee = _fastlanePayee;
        escrowDuration = _escrowDuration;

        escrowAddress = address(_escrowContract);

        _dirtySalt = keccak256(
            abi.encodePacked(
                block.chainid,
                escrowAddress,
                "UntrustedExecutionEnvironment", 
                address(this)
            )
        );

        SketchyStorageEnvironment _dirtyContract = new SketchyStorageEnvironment{
            salt: _dirtySalt
        }(PROTOCOL_SHARE, escrowAddress);

        dirtyAddress = address(_dirtyContract);
    }

    // TODO: Consider limiting who can call this
    function revive() external {
        if (dirtyAddress.codehash == bytes32(0)) {
            new SketchyStorageEnvironment{
                salt: _dirtySalt
            }(PROTOCOL_SHARE, escrowAddress);
        }
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
        ))))); 
    }

    function _getDirtyAddress() internal view returns (address) {
        return dirtyAddress;
    }

} 