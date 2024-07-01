//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Storage } from "./Storage.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";

/// @title SafetyLocks
/// @author FastLane Labs
/// @notice SafetyLocks manages the locking and unlocking of the Atlas environment during the execution of a metacall
/// transaction.
abstract contract SafetyLocks is Storage {
    using CallBits for uint32;

    constructor(
        uint256 escrowDuration,
        address verification,
        address simulator,
        address initialSurchargeRecipient
    )
        Storage(escrowDuration, verification, simulator, initialSurchargeRecipient)
    { }

    /// @notice Sets the Atlas lock to the specified execution environment.
    /// @param dConfig The DAppConfig of the current DAppControl contract.
    /// @param executionEnvironment The address of the execution environment to set the lock to.
    function _setEnvironmentLock(DAppConfig memory dConfig, address executionEnvironment) internal {
        if (T_lock.activeEnvironment != _UNLOCKED) revert AlreadyInitialized();

        // Initialize the Lock
        T_lock = Lock({
            activeEnvironment: executionEnvironment,
            phase: dConfig.callConfig.needsPreOpsCall() ? uint8(ExecutionPhase.PreOps) : uint8(ExecutionPhase.UserOperation),
            callConfig: dConfig.callConfig
        });
    }

    modifier withLockPhase(ExecutionPhase executionPhase) {
        T_lock.phase = uint8(executionPhase);
        _;
    }

    /// @notice Builds an Context struct with the specified parameters, called at the start of
    /// `_preOpsUserExecutionIteration`.
    /// @param dConfig The DAppConfig of the current DAppControl contract.
    /// @param executionEnvironment The address of the current Execution Environment.
    /// @param userOpHash The UserOperation hash.
    /// @param bundler The address of the bundler.
    /// @param solverOpCount The count of SolverOperations.
    /// @param isSimulation Boolean indicating whether the call is a simulation or not.
    /// @return An Context struct initialized with the provided parameters.
    function _buildContext(
        DAppConfig memory dConfig,
        address executionEnvironment,
        bytes32 userOpHash,
        address bundler,
        uint8 solverOpCount,
        bool isSimulation
    )
        internal
        pure
        returns (Context memory)
    {
        return Context({
            executionEnvironment: executionEnvironment,
            userOpHash: userOpHash,
            bundler: bundler,
            solverSuccessful: false,
            paymentsSuccessful: false,
            solverIndex: 0,
            solverCount: solverOpCount,
            phase: dConfig.callConfig.needsPreOpsCall() ? uint8(ExecutionPhase.PreOps) : uint8(ExecutionPhase.UserOperation),
            solverOutcome: 0,
            bidFind: false,
            isSimulation: isSimulation,
            callDepth: 0
        });
    }

    /// @notice Releases the Atlas lock, and resets the associated transient storage variables. Called at the end of
    /// `metacall`.
    function _releaseAccountingLock() internal {
        T_lock =
            Lock({ activeEnvironment: _UNLOCKED, phase: uint8(ExecutionPhase.Uninitialized), callConfig: uint32(0) });
        T_solverLock = _UNLOCKED_UINT;
        T_claims = type(uint256).max;
        T_fees = type(uint256).max;
        T_withdrawals = type(uint256).max;
        T_deposits = type(uint256).max;
        T_writeoffs = type(uint256).max;
    }

    /// @notice Returns the address of the currently active Execution Environment, if any.
    function activeEnvironment() external view returns (address) {
        return T_lock.activeEnvironment;
    }

    function phase() external view returns (ExecutionPhase) {
        return ExecutionPhase(T_lock.phase);
    }

    /// @notice Returns the current lock state of Atlas.
    /// @return Boolean indicating whether Atlas is in a locked state or not.
    function isUnlocked() external view returns (bool) {
        return T_lock.activeEnvironment == _UNLOCKED;
    }
}
