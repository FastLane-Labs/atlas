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

    function initializeEscrowLock(
        address executionEnvironment,
        uint256 gasMarker,
        uint256 userOpValue
    )
        external
        payable
    {
        _setAtlasLock(executionEnvironment, gasMarker, userOpValue);
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
        returns (EscrowKey memory escrowKey)
    {
        return _buildEscrowLock(dConfig, executionEnvironment, userOpHash, bundler, solverOpCount, isSimulation);
    }

    function releaseEscrowLock() external {
        _releaseAtlasLock();
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

    function test_setAtlasLock() public {
        uint256 gasMarker = 222;
        uint256 userOpValue = 333;
        uint256 msgValue = 444;

        safetyLocks.setLock(address(2));
        vm.expectRevert(AtlasErrors.AlreadyInitialized.selector);
        safetyLocks.initializeEscrowLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);
        safetyLocks.setLock(address(1)); // Reset to UNLOCKED

        safetyLocks.initializeEscrowLock{ value: msgValue }(executionEnvironment, gasMarker, userOpValue);

        uint256 rawClaims = (gasMarker + safetyLocks.FIXED_GAS_OFFSET()) * tx.gasprice;
        uint256 expectedClaims = rawClaims + ((rawClaims * safetyLocks.SURCHARGE_RATE()) / safetyLocks.SURCHARGE_SCALE());

        assertEq(safetyLocks.lock(), executionEnvironment);
        assertEq(safetyLocks.claims(), expectedClaims);
        assertEq(safetyLocks.withdrawals(), userOpValue);
        assertEq(safetyLocks.deposits(), msgValue);
    }

    function test_buildEscrowLock() public {
        DAppConfig memory dConfig = DAppConfig({ to: address(10), callConfig: 0, bidToken: address(0), solverGasLimit: 1_000_000});

        safetyLocks.initializeEscrowLock(executionEnvironment, 0, 0);
        EscrowKey memory key = safetyLocks.buildEscrowLock(dConfig, executionEnvironment, bytes32(0), address(0), 0, false);
        assertEq(executionEnvironment, key.executionEnvironment);
        assertEq(executionEnvironment, key.addressPointer);
    }

    function test_releaseAtlasLock() public {
        vm.expectRevert(AtlasErrors.NotInitialized.selector);
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
