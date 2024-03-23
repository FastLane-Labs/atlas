//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafetyBits } from "../libraries/SafetyBits.sol";
import { CallBits } from "../libraries/CallBits.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";

import "../types/LockTypes.sol";

import { Storage } from "./Storage.sol";

// import "forge-std/Test.sol";

abstract contract SafetyLocks is Storage {
    using CallBits for uint32;

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
        claims = rawClaims + ((rawClaims * SURCHARGE) / 10_000_000);

        // Set any withdraws or deposits
        withdrawals = userOpValue;
        deposits = msg.value;
    }

    // Used in AtlETH
    function _checkIfUnlocked() internal view {
        if (lock != UNLOCKED) revert AlreadyInitialized();
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
        return EscrowKey({
            executionEnvironment: executionEnvironment,
            userOpHash: userOpHash,
            bundler: bundler,
            addressPointer: executionEnvironment,
            solverSuccessful: false,
            paymentsSuccessful: false,
            callIndex: dConfig.callConfig.needsPreOpsCall() ? 0 : 1,
            callCount: solverOpCount + 3,
            lockState: 0,
            solverOutcome: 0,
            bidFind: false,
            isSimulation: isSimulation,
            callDepth: 0
        });
    }

    function _releaseAtlasLock() internal {
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
