// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafetyLocks } from "src/contracts/atlas/SafetyLocks.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/UserCallTypes.sol";

contract MockSafetyLocks is SafetyLocks {
    constructor() SafetyLocks(0, address(0), address(0), address(0)) { }

    function initializeAtlasLock(
        UserOperation calldata userOp,
        address executionEnvironment,
        uint32 callConfig,
        uint256 gasMarker
    ) external payable {
        _setAtlasLock(userOp, executionEnvironment, callConfig, gasMarker);
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
        view
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

        address userAddr = address(3456);
        address controlAddr = address(4567);
        uint32 callConfig = 5678;

        UserOperation memory userOp;
        userOp.from = userAddr;
        userOp.control = controlAddr;
        userOp.value = userOpValue;

        safetyLocks.setLock(address(2));
        vm.expectRevert(AtlasErrors.AlreadyInitialized.selector);
        safetyLocks.initializeAtlasLock{ value: msgValue }(userOp, executionEnvironment, callConfig, gasMarker);
        safetyLocks.setLock(address(1)); // Reset to UNLOCKED

        safetyLocks.initializeAtlasLock{ value: msgValue }(userOp, executionEnvironment, callConfig, gasMarker);

        uint256 rawClaims = (gasMarker + 1) * tx.gasprice;
        uint256 expectedClaims = rawClaims + ((rawClaims * safetyLocks.SURCHARGE_RATE()) / safetyLocks.SURCHARGE_SCALE());

        assertEq(safetyLocks.lock(), executionEnvironment);
        assertEq(safetyLocks.claims(), expectedClaims);
        assertEq(safetyLocks.withdrawals(), userOpValue);
        assertEq(safetyLocks.deposits(), msgValue);
    }

    function test_buildEscrowLock() public {
        DAppConfig memory dConfig = DAppConfig({ to: address(10), callConfig: 0, bidToken: address(0), solverGasLimit: 1_000_000});
        UserOperation memory userOp;

        safetyLocks.initializeAtlasLock(userOp, executionEnvironment, 0, 0);
        EscrowKey memory key = safetyLocks.buildEscrowLock(dConfig, executionEnvironment, bytes32(0), address(0), 0, false);
        assertEq(executionEnvironment, key.executionEnvironment);
        assertEq(executionEnvironment, key.addressPointer);
    }

    function test_releaseAtlasLock() public {
        UserOperation memory userOp;

        vm.expectRevert(AtlasErrors.NotInitialized.selector);
        safetyLocks.releaseEscrowLock();

        safetyLocks.initializeAtlasLock(userOp, executionEnvironment, 0, 0);
        safetyLocks.releaseEscrowLock();
        assertEq(safetyLocks.lock(), address(1));
        assertEq(safetyLocks.solver(), address(1));
        assertEq(safetyLocks.claims(), type(uint256).max);
        assertEq(safetyLocks.withdrawals(), type(uint256).max);
        assertEq(safetyLocks.deposits(), type(uint256).max);
    }

    function test_activeEnvironment() public {
        UserOperation memory userOp;
        safetyLocks.initializeAtlasLock(userOp, executionEnvironment, 0, 0);
        assertEq(safetyLocks.activeEnvironment(), executionEnvironment);
    }
}
