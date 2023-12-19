// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { SafetyLocks } from "../src/contracts/atlas/SafetyLocks.sol";
import { FastLaneErrorsEvents } from "../src/contracts/types/Emissions.sol";

import "../src/contracts/types/DAppApprovalTypes.sol";
import "../src/contracts/types/LockTypes.sol";

contract MockSafetyLocks is SafetyLocks {
    constructor() SafetyLocks(0, address(0), address(0)) { }

    function initializeEscrowLock(
        address executionEnvironment,
        uint256 gasMarker,
        uint256 userOpValue
    )
        external
        payable
    {
        _initializeEscrowLock(executionEnvironment, gasMarker, userOpValue);
    }

    function checkIfUnlocked() external view {
        _checkIfUnlocked();
    }

    function buildEscrowLock(
        DAppConfig calldata dConfig,
        address executionEnvironment,
        uint8 solverOpCount,
        bool isSimulation
    )
        external
        view
        returns (EscrowKey memory escrowKey)
    {
        return _buildEscrowLock(dConfig, executionEnvironment, solverOpCount, isSimulation);
    }

    function releaseEscrowLock() external {
        _releaseEscrowLock();
    }

    function setLock(address _lock) external {
        lock = _lock;
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

    function test_initializeEscrowLock() public {
        uint256 gasMarker = 222;
        uint256 userOpValue = 333;
        uint256 msgValue = 444;

        safetyLocks.initializeEscrowLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);

        uint256 rawClaims = (gasMarker + 1) * tx.gasprice;
        uint256 expectedClaims = rawClaims + ((rawClaims * safetyLocks.SURCHARGE()) / safetyLocks.SURCHARGE_BASE());

        assertEq(safetyLocks.lock(), executionEnvironment);
        assertEq(safetyLocks.claims(), expectedClaims);
        assertEq(safetyLocks.withdrawals(), userOpValue);
        assertEq(safetyLocks.deposits(), msgValue);
    }

    function test_checkIfUnlocked() public {
        safetyLocks.setLock(address(2));
        vm.expectRevert(FastLaneErrorsEvents.AlreadyInitialized.selector);
        safetyLocks.checkIfUnlocked();
        safetyLocks.setLock(address(1)); // Reset to UNLOCKED

        safetyLocks.setClaims(1);
        vm.expectRevert(FastLaneErrorsEvents.AlreadyInitialized.selector);
        safetyLocks.checkIfUnlocked();
        safetyLocks.setClaims(type(uint256).max); // Reset

        safetyLocks.setWithdrawals(1);
        vm.expectRevert(FastLaneErrorsEvents.AlreadyInitialized.selector);
        safetyLocks.checkIfUnlocked();
        safetyLocks.setWithdrawals(type(uint256).max); // Reset

        safetyLocks.setDeposits(1);
        vm.expectRevert(FastLaneErrorsEvents.AlreadyInitialized.selector);
        safetyLocks.checkIfUnlocked();
        safetyLocks.setDeposits(type(uint256).max); // Reset
    }

    function test_buildEscrowLock() public {
        DAppConfig memory dConfig = DAppConfig({ to: address(10), callConfig: 0, bidToken: address(0) });

        vm.expectRevert(FastLaneErrorsEvents.NotInitialized.selector);
        safetyLocks.buildEscrowLock(dConfig, executionEnvironment, 0, false);

        safetyLocks.initializeEscrowLock(executionEnvironment, 0, 0);
        safetyLocks.buildEscrowLock(dConfig, executionEnvironment, 0, false);
        // No assertion needed, the test is valid if it doesn't revert
    }

    function test_releaseEscrowLock() public {
        vm.expectRevert(FastLaneErrorsEvents.NotInitialized.selector);
        safetyLocks.releaseEscrowLock();

        safetyLocks.initializeEscrowLock(executionEnvironment, 0, 0);
        safetyLocks.releaseEscrowLock();
        assertEq(safetyLocks.lock(), address(1));
        assertEq(safetyLocks.solver(), address(1));
        assertEq(safetyLocks.claims(), type(uint256).max);
        assertEq(safetyLocks.withdrawals(), type(uint256).max);
        assertEq(safetyLocks.deposits(), type(uint256).max);
    }

    function test_activeEnvironment() public {
        safetyLocks.initializeEscrowLock(executionEnvironment, 0, 0);
        assertEq(safetyLocks.activeEnvironment(), executionEnvironment);
    }
}
