//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
//import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";

import "../types/LockTypes.sol";
import {ProtocolCall} from "../types/CallTypes.sol";

// NOTE: IPermit69 only works inside of the Atlas environment - specifically
// inside of the custom ExecutionEnvironments that each user deploys when
// interacting with Atlas in a manner controlled by the DeFi protocol.

// The name comes from the reciprocal nature of the token transfers. Both
// the user and the ProtocolControl can transfer tokens from the User
// and the ProtocolControl contracts... but only if they each have granted
// token approval to the Atlas main contract, and only during specific phases
// of the Atlas execution process.
abstract contract Permit69 {
    using SafeTransferLib for ERC20;

    // Virtual Functions defined by other Atlas modules
    function _getExecutionEnvironmentCustom(address user, bytes32 controlCodeHash, address protocolControl, uint16 callConfig)
        internal
        view
        virtual
        returns (address environment);

    function environment() public view virtual returns (address);

    // Transfer functions
    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user, 
        address protocolControl,
        uint16 callConfig
    ) external {
        // Verify that the caller is legitimate
        // NOTE: Use the *current* protocolControl's codehash to help mitigate social engineering bamboozles if, for example, 
        // a DAO is having internal issues. 
        require(msg.sender == _getExecutionEnvironmentCustom(user, protocolControl.codehash, protocolControl, callConfig), "ERR-T001 UserTransfer");

        // Verify that the user is in control (or approved the protocol's control) of the ExecutionEnvironment
        require(msg.sender == environment(), "ERR-T002 UserTransfer");

        // Transfer token
        ERC20(token).safeTransferFrom(user, destination, amount);
    }

    function transferProtocolERC20(
        address token,
        address destination,
        uint256 amount,
        address user, 
        address protocolControl,
        uint16 callConfig
    ) external {
        // Verify that the caller is legitimate
        require(msg.sender == _getExecutionEnvironmentCustom(user, protocolControl.codehash, protocolControl, callConfig), "ERR-T003 ProtocolTransfer");

        // Verify that the user is in control (or approved the protocol's control) of the ExecutionEnvironment
        require(msg.sender == environment(), "ERR-T004 ProtocolTransfer");

        // Transfer token
        ERC20(token).safeTransferFrom(protocolControl, destination, amount);
    }
}