//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafetyBits } from "../libraries/SafetyBits.sol";
import { CallBits } from "../libraries/CallBits.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";

import "../types/LockTypes.sol";

import { EXECUTION_PHASE_OFFSET } from "../libraries/SafetyBits.sol";

import { Storage } from "./Storage.sol";

// import "forge-std/Test.sol";

abstract contract SafetyLocks is Storage {
    using CallBits for uint32;

    uint16 internal constant _ACTIVE_X_PRE_OPS_X_UNSET =
        uint16(1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps)));

    uint16 internal constant _ACTIVE_X_USER_X_UNSET =
        uint16(1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation)));

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        Storage(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    function _setAtlasLock(address executionEnvironment, uint256 gasMarker, uint256 userOpValue) internal {
        _checkIfUnlocked();
        // Initialize the Lock
        lock = executionEnvironment;

        // Set the claimed amount
        uint256 rawClaims = (gasMarker + 1) * tx.gasprice;
        claims = rawClaims + ((rawClaims * SURCHARGE) / SURCHARGE_BASE);

        // Set any withdraws or deposits
        withdrawals = userOpValue;
        deposits = msg.value;
    }

    // TODO are all these checks necessary? More gas efficient was to check if unlocked?
    // Used in AtlETH
    function _checkIfUnlocked() internal view {
        if (lock != UNLOCKED) revert AlreadyInitialized();
        if (claims != type(uint256).max) revert AlreadyInitialized();
        if (withdrawals != type(uint256).max) revert AlreadyInitialized();
        if (deposits != type(uint256).max) revert AlreadyInitialized();
    }

    function _buildEscrowLock(
        DAppConfig calldata dConfig,
        address executionEnvironment,
        bytes32 userOpHash,
        address bundler,
        uint8 solverOpCount,
        bool isSimulation
    )
        internal
        pure
        returns (EscrowKey memory)
    {
        bool needsPreOps = dConfig.callConfig.needsPreOpsCall();

        return EscrowKey({
            executionEnvironment: executionEnvironment,
            userOpHash: userOpHash,
            bundler: bundler,
            addressPointer: executionEnvironment,
            solverSuccessful: false,
            paymentsSuccessful: false,
            callIndex: needsPreOps ? 0 : 1,
            callCount: solverOpCount + 3,
            lockState: needsPreOps ? _ACTIVE_X_PRE_OPS_X_UNSET : _ACTIVE_X_USER_X_UNSET,
            solverOutcome: 0,
            bidFind: false,
            isSimulation: isSimulation,
            callDepth: 0
        });
    }

    function _releaseEscrowLock() internal {
        if (lock == UNLOCKED) revert NotInitialized();
        lock = UNLOCKED;
        _solverLock = _UNLOCKED_UINT;
        claims = type(uint256).max;
        withdrawals = type(uint256).max;
        deposits = type(uint256).max;
    }

    function activeEnvironment() external view returns (address) {
        return lock;
    }

    function isUnlocked() external view returns (bool) {
        return lock == UNLOCKED;
    }
}
