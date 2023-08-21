//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

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

    uint16 internal constant _EXECUTION_PHASE_OFFSET = uint16(type(BaseLock).max);

    // NOTE: No user transfers allowed during UserRefund or HandlingPayments
    uint16 internal constant _SAFE_USER_TRANSFER = uint16(
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging))
            | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserCall))
            | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
    );

    // NOTE: No protocol transfers allowed during UserCall
    uint16 internal constant _SAFE_PROTOCOL_TRANSFER = uint16(
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging))
            | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
            | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserRefund))
            | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
    );

    // Virtual Functions defined by other Atlas modules
    function _getExecutionEnvironmentCustom(
        address user,
        bytes32 controlCodeHash,
        address protocolControl,
        uint16 callConfig
    ) internal view virtual returns (address environment);

    function _getLockState() internal view virtual returns (EscrowKey memory);

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
        // NOTE: Use the *current* protocolControl's codehash to help mitigate social engineering bamboozles.
        _verifyCallerIsExecutionEnv(user, protocolControl.codehash, protocolControl, callConfig);

        // Verify that the user is in control (or approved the protocol's control) of the ExecutionEnvironment
        _verifyLockState(_SAFE_USER_TRANSFER);

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
        _verifyCallerIsExecutionEnv(user, protocolControl.codehash, protocolControl, callConfig);

        // Verify that the protocol is in control of the ExecutionEnvironment
        _verifyLockState(_SAFE_PROTOCOL_TRANSFER);

        // Transfer token
        ERC20(token).safeTransferFrom(protocolControl, destination, amount);
    }

    function _verifyCallerIsExecutionEnv(
        address user,
        bytes32 controlCodehash,
        address protocolControl,
        uint16 callConfig
    ) internal view {
        require(
            msg.sender == _getExecutionEnvironmentCustom(user, controlCodehash, protocolControl, callConfig),
            "ERR-T001 ProtocolTransfer"
        );
    }

    function _verifyLockState(uint16 safeExecutionPhaseSet) internal view {
        require(_getLockState().lockState & safeExecutionPhaseSet != 0, "ERR-T002 ProtocolTransfer");
    }
}
