//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ITokenTransfers} from "../interfaces/ITokenTransfers.sol";

contract ExecutionBase {

    // These functions only work inside of the ExecutionEnvironment (mimic)
    // via delegatecall, but can be added to ProtocolControl as funcs that 
    // can be used during ProtocolControl's delegated funcs
    
    // Returns the address(ProtocolControl).codehash for the calling
    // ExecutionEnvironment's ProtocolControl
    function _controlCodeHash() internal pure returns (bytes32 controlCodeHash) {
        assembly {
            controlCodeHash := calldataload(sub(calldatasize(), 32))
        }
    }

    function _config() internal pure returns (uint16 config) {
        assembly {
            config := shr(240, calldataload(sub(calldatasize(), 34)))
        }
    }

    function _control() internal pure returns (address control) {
        assembly {
            control := shr(96, calldataload(sub(calldatasize(), 54)))
        }
    }

    function _user() internal pure returns (address user) {
        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 74)))
        }
    }

    function _transferUserERC20(
        address token,
        address destination,
        uint256 amount
    ) internal {
        ITokenTransfers(msg.sender).transferUserERC20(
            token, destination, amount, _user(), _control(), _config()
        );
    }

    function _transferProtocolERC20(
        address token,
        address destination,
        uint256 amount
    ) internal {
        ITokenTransfers(msg.sender).transferProtocolERC20(
            token, destination, amount, _user(), _control(), _config()
        );
    }
}