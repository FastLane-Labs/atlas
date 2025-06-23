//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Storage } from "./Storage.sol";
import { CallBits } from "../libraries/CallBits.sol";
import "../types/ConfigTypes.sol";
import "../types/LockTypes.sol";

/// @title SafetyLocks
/// @author FastLane Labs
/// @notice SafetyLocks manages the locking and unlocking of the Atlas environment during the execution of a metacall
/// transaction.
abstract contract SafetyLocks is Storage {
    using CallBits for uint32;

    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator
    )
        Storage(escrowDuration, atlasSurchargeRate, verification, simulator, initialSurchargeRecipient, l2GasCalculator)
    { }

    /// @notice Sets the Atlas lock to the specified execution environment.
    /// @param dConfig The DAppConfig of the current DAppControl contract.
    /// @param executionEnvironment The address of the execution environment to set the lock to.
    function _setEnvironmentLock(DAppConfig memory dConfig, address executionEnvironment) internal {
        if (!_isUnlocked()) revert AlreadyInitialized();

        // Initialize the Lock
        _setLock({
            activeEnvironment: executionEnvironment,
            callConfig: dConfig.callConfig,
            phase: uint8(ExecutionPhase.PreOps)
        });
    }

    modifier withLockPhase(ExecutionPhase executionPhase) {
        _setLockPhase(uint8(executionPhase));
        _;
    }

    /// @notice Builds an Context struct with the specified parameters, called at the start of
    /// `_preOpsUserExecutionIteration`.
    /// @param userOpHash The hash of the UserOperation.
    /// @param executionEnvironment The address of the execution environment.
    /// @param bundler The address of the bundler.
    /// @param dappGasLimit The DAppControl's gas limit for preOps and allocateValue hooks.
    /// @param solverOpCount The count of SolverOperations.
    /// @param isSimulation Whether the current execution is a simulation.
    /// @return An Context struct initialized with the provided parameters.
    function _buildContext(
        bytes32 userOpHash,
        address executionEnvironment,
        address bundler,
        uint32 dappGasLimit,
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
            solverIndex: 0,
            solverCount: solverOpCount,
            phase: uint8(ExecutionPhase.PreOps),
            solverOutcome: 0,
            bidFind: false,
            isSimulation: isSimulation,
            callDepth: 0,
            dappGasLeft: dappGasLimit
        });
    }
}
