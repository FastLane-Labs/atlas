// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import { SafetyLocks } from "src/contracts/atlas/SafetyLocks.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/LockTypes.sol";

contract MockSafetyLocks is SafetyLocks {
    constructor() SafetyLocks(0, address(0), address(0), address(0)) { }

    function initializeLock(
        address executionEnvironment,
        uint256 gasMarker,
        uint256 userOpValue
    )
        external
        payable
    {
        DAppConfig memory dConfig;
        _setEnvironmentLock(dConfig, executionEnvironment);
        // _initializeAccountingValues(gasMarker);
    }

    function buildEscrowLock(
        address executionEnvironment,
        bytes32 userOpHash,
        address bundler,
        uint8 solverOpCount,
        bool isSimulation
    )
        external
        pure
        returns (Context memory ctx)
    {
        return _buildContext(executionEnvironment, userOpHash, bundler, solverOpCount, isSimulation);
    }

    function setLock(address _activeEnvironment) external {
        _setLock({
            activeEnvironment: _activeEnvironment,
            phase: uint8(ExecutionPhase.Uninitialized),
            callConfig: uint32(0)
        });
    }

    function setClaims(uint256 _claims) external {
        _setClaims(_claims);
    }

    function setWithdrawals(uint256 _withdrawals) external {
        _setWithdrawals(_withdrawals);
    }

    function setDeposits(uint256 _deposits) external {
        _setDeposits(_deposits);
    }

    function setFees(uint256 _fees) external {
        _setFees(_fees);
    }

    function setWriteoffs(uint256 _writeoffs) external {
        _setWriteoffs(_writeoffs);
    }
}

contract SafetyLocksTest is Test {
    MockSafetyLocks public safetyLocks;
    address executionEnvironment = makeAddr("executionEnvironment");

    function setUp() public {
        safetyLocks = new MockSafetyLocks();
    }

    function test_setEnvironmentLock() public {
        // FIXME: fix before merging spearbit-reaudit branch
        vm.skip(true);

        uint256 gasMarker = 222;
        uint256 userOpValue = 333;
        uint256 msgValue = 444;

        safetyLocks.setLock(address(2));
        vm.expectRevert(AtlasErrors.AlreadyInitialized.selector);
        safetyLocks.initializeLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);
        safetyLocks.setLock(address(1)); // Reset to UNLOCKED

        safetyLocks.initializeLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);


        (address activeEnv, uint32 callConfig, uint8 phase) = safetyLocks.lock();

        assertEq(activeEnv, executionEnvironment);
        assertEq(phase, uint8(ExecutionPhase.UserOperation));
        assertEq(callConfig, uint32(0));
    }

    function test_buildContext() public {
        safetyLocks.initializeLock(executionEnvironment, 0, 0);
        Context memory ctx = safetyLocks.buildEscrowLock(executionEnvironment, bytes32(0), address(0), 0, false);
        assertEq(executionEnvironment, ctx.executionEnvironment);
    }
}
