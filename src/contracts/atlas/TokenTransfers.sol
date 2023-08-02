//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import "../types/LockTypes.sol";
import {ProtocolCall} from "../types/CallTypes.sol";

abstract contract TokenTransfers {
    using SafeTransferLib for ERC20;

    uint16 internal constant _EXECUTION_PHASE_OFFSET = uint16(type(BaseLock).max);
    
    // NOTE: No user transfers allowed during UserRefund or HandlingPayments
    uint16 internal constant _SAFE_USER_TRANSFER = uint16(
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging)) | 
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserCall)) |
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
    );

    // NOTE: No protocol transfers allowed during UserCall 
    uint16 internal constant _SAFE_PROTOCOL_TRANSFER = uint16(
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging)) | 
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments)) |
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserRefund)) |
        1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
    );

    // Virtual Functions defined by other Atlas modules
    function _getExecutionEnvironmentCustom(address user, bytes32 controlCodeHash, address protocolControl, uint16 callConfig)
        internal
        view
        virtual
        returns (address environment);

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
        require(msg.sender == _getExecutionEnvironmentCustom(user, protocolControl.codehash, protocolControl, callConfig), "ERR-T001 ProtocolTransfer");

        // Verify that the user is in control (or approved the protocol's control) of the ExecutionEnvironment
        require(_getLockState().lockState & _SAFE_USER_TRANSFER != 0, "ERR-T002 ProtocolTransfer");

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

        // Verify that the protocol is in control of the ExecutionEnvironment
        require(_getLockState().lockState & _SAFE_PROTOCOL_TRANSFER != 0, "ERR-T004 ProtocolTransfer");

        // Transfer token
        ERC20(token).safeTransferFrom(protocolControl, destination, amount);
    }
}