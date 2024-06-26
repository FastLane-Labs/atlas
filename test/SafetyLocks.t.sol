// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafetyLocks } from "src/contracts/atlas/SafetyLocks.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/DAppApprovalTypes.sol";
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
        _setAccountingLock(dConfig, executionEnvironment, gasMarker, userOpValue);
    }

    function buildEscrowLock(
        DAppConfig calldata dConfig,
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
        return _buildContext(dConfig, executionEnvironment, userOpHash, bundler, solverOpCount, isSimulation);
    }

    function releaseEscrowLock() external {
        _releaseAccountingLock();
    }

    function setLock(address _activeEnvironment) external {
        lock = Lock({
            activeEnvironment: _activeEnvironment,
            phase: uint8(ExecutionPhase.Uninitialized),
            callConfig: uint32(0)
        });
    }

    function setClaims(uint256 _claims) external {
        claims = _claims;
    }

    function setWithdrawals(uint256 _withdrawals) external {
        withdrawals = _withdrawals;
    }

    function setDeposits(uint256 _deposits) external {
        deposits = _deposits;
    }
}

contract SafetyLocksTest is Test {
    MockSafetyLocks public safetyLocks;
    address executionEnvironment = makeAddr("executionEnvironment");

    function setUp() public {
        safetyLocks = new MockSafetyLocks();
    }

    function test_setAccountingLock() public {
        uint256 gasMarker = 222;
        uint256 userOpValue = 333;
        uint256 msgValue = 444;

        safetyLocks.setLock(address(2));
        vm.expectRevert(AtlasErrors.AlreadyInitialized.selector);
        safetyLocks.initializeLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);
        safetyLocks.setLock(address(1)); // Reset to UNLOCKED

        safetyLocks.initializeLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);

        uint256 rawClaims = (gasMarker + safetyLocks.FIXED_GAS_OFFSET()) * tx.gasprice;
        uint256 expectedClaims = rawClaims * (safetyLocks.SURCHARGE_SCALE() + safetyLocks.ATLAS_SURCHARGE_RATE() + safetyLocks.BUNDLER_SURCHARGE_RATE()) / safetyLocks.SURCHARGE_SCALE();

        assertEq(safetyLocks.activeEnvironment(), executionEnvironment);
        assertEq(safetyLocks.claims(), expectedClaims);
        assertEq(safetyLocks.withdrawals(), userOpValue);
        assertEq(safetyLocks.deposits(), msgValue);
    }

    function test_buildContext() public {
        DAppConfig memory dConfig = DAppConfig({ to: address(10), callConfig: 0, bidToken: address(0), solverGasLimit: 1_000_000});

        safetyLocks.initializeLock(executionEnvironment, 0, 0);
        Context memory ctx = safetyLocks.buildEscrowLock(dConfig, executionEnvironment, bytes32(0), address(0), 0, false);
        assertEq(executionEnvironment, ctx.executionEnvironment);
    }

    function test_releaseAccountingLock() public {

        safetyLocks.initializeLock(executionEnvironment, 0, 0);
        safetyLocks.releaseEscrowLock();
        assertEq(safetyLocks.activeEnvironment(), address(1));
        assertEq(safetyLocks.solver(), address(1));
        assertEq(safetyLocks.claims(), type(uint256).max);
        assertEq(safetyLocks.withdrawals(), type(uint256).max);
        assertEq(safetyLocks.deposits(), type(uint256).max);
    }

    function test_activeEnvironment() public {
        safetyLocks.initializeLock(executionEnvironment, 0, 0);
        assertEq(safetyLocks.activeEnvironment(), executionEnvironment);
    }
}
