//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { Escrow } from "./Escrow.sol";
import { SketchyStorageEnvironment } from "./SketchyStorage.sol";
import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";

contract FastLaneFactory is Ownable, ReentrancyGuard {

    uint32 immutable public escrowDuration;
    address immutable public fastLanePayee;

    bytes32 constant internal _DIRTY_SALT = keccak256(
        abi.encodePacked(
            block.chainid,
            escrowAddress,
            "UntrustedExecutionEnvironment", 
            address(this)
        )
    );

    FastLaneEscrow internal _escrowContract = new FastLaneEscrow(uint32(64));

    address constant public ESCROW_ADDRESS = address(_escrowContract);

    SketchyStorageEnvironment internal _dirtyContract = new SketchyStorageEnvironment{
        salt: _DIRTY_SALT
    }(ESCROW_ADDRESS);

    address constant public DIRTY_ADDRESS = address(_dirtyContract);

    constructor(
            address _fastlanePayee,
            uint32 _escrowDuration

    ) {
        fastLanePayee = _fastlanePayee;
        escrowDuration = _escrowDuration;
    }

    // TODO: Consider limiting who can call this
    function revive() external {
        if (DIRTY_ADDRESS.codehash == bytes(0)) {
            _dirtyContract = new SketchyStorageEnvironment{
                salt: _DIRTY_SALT
            }(ESCROW_ADDRESS);
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

    function _getDirtyAddress() internal view returns (address dirtyAddress) {
        return dirtyAddress;
    }

} 