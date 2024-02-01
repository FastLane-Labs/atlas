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
import { FastLaneErrorsEvents, AtlasEvents } from "../types/Emissions.sol";

// import "forge-std/Test.sol";

abstract contract SafetyLocks is Storage, FastLaneErrorsEvents, AtlasEvents {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;

    event EscrowLocked(address indexed executionEnvironment, uint256 claims);

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        Storage(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    function _initializeEscrowLock(address executionEnvironment, uint256 gasMarker, uint256 userOpValue) internal {
        _checkIfUnlocked();
        // Initialize the Lock
        lock = executionEnvironment;

        // Set the claimed amount
        uint256 rawClaims = (gasMarker + 1) * tx.gasprice;
        claims = rawClaims + ((rawClaims * SURCHARGE) / SURCHARGE_BASE);

        // Set any withdraws or deposits
        withdrawals = userOpValue;
        deposits = msg.value;

        emit EscrowLocked(executionEnvironment, claims);
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
        uint8 solverOpCount,
        bool isSimulation
    )
        internal
        view
        returns (EscrowKey memory self)
    {
        // TODO: can we bypass this check?
        if (lock != executionEnvironment) revert NotInitialized();

        self = self.initializeEscrowLock(
            dConfig.callConfig.needsPreOpsCall(), solverOpCount, executionEnvironment, isSimulation
        );
    }

    function _releaseEscrowLock() internal {
        if (lock == UNLOCKED) revert NotInitialized();
        lock = UNLOCKED;
        solver = UNLOCKED;
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
