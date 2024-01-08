// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { GasAccounting } from "../src/contracts/atlas/GasAccounting.sol";
import { FastLaneErrorsEvents } from "../src/contracts/types/Emissions.sol";

import { EscrowBits } from "../src/contracts/libraries/EscrowBits.sol";

import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/SolverCallTypes.sol";

contract MockGasAccounting is GasAccounting, Test {
    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator
    )
        GasAccounting(_escrowDuration, _verification, _simulator)
    { }

    function balanceOf(address account) external view returns (uint128, uint128) {
        return (_balanceOf[account].balance, _balanceOf[account].unbonding);
    }

    function initializeEscrowLock(address executionEnvironment, uint256 gasMarker, uint256 userOpValue) external {
        _initializeEscrowLock(executionEnvironment, gasMarker, userOpValue);
    }

    function assign(address owner, uint256 value) external returns (bool) {
        return _assign(owner, value);
    }

    function credit(address owner, uint256 value) external {
        _credit(owner, value);
    }

    function trySolverLock(SolverOperation calldata solverOp) external returns (bool) {
        return _trySolverLock(solverOp);
    }

    function releaseSolverLock(SolverOperation calldata solverOp, uint256 gasWaterMark, uint256 result) external {
        _releaseSolverLock(solverOp, gasWaterMark, result);
    }

    function settle(address winningSolver, address bundler) external {
        _settle(winningSolver, bundler);
    }

    function increaseBondedBalance(address account, uint256 amount) external {
        deal(address(this), amount);
        accessData[account].bonded += uint128(amount);
        bondedTotalSupply += uint128(amount);
    }

    function increaseUnbondingBalance(address account, uint256 amount) external {
        deal(address(this), amount);
        _balanceOf[account].unbonding += uint128(amount);
        bondedTotalSupply += uint128(amount);
    }
}

contract GasAccountingTest is Test {
    MockGasAccounting public mockGasAccounting;
    address executionEnvironment = makeAddr("executionEnvironment");

    uint256 initialClaims;
    SolverOperation solverOp;

    function setUp() public {
        mockGasAccounting = new MockGasAccounting(0, address(0), address(0));
        uint256 gasMarker = gasleft();

        mockGasAccounting.initializeEscrowLock(executionEnvironment, gasMarker, 0);

        initialClaims = getInitialClaims(gasMarker);
        solverOp.from = makeAddr("solver");
    }

    function getInitialClaims(uint256 gasMarker) public view returns (uint256 claims) {
        uint256 rawClaims = (gasMarker + 1) * tx.gasprice;
        claims = rawClaims + ((rawClaims * mockGasAccounting.SURCHARGE()) / mockGasAccounting.SURCHARGE_BASE());
    }

    function test_validateBalances() public {
        assertFalse(mockGasAccounting.validateBalances());

        mockGasAccounting.trySolverLock(solverOp);
        mockGasAccounting.reconcile{ value: initialClaims }(executionEnvironment, solverOp.from, 0);

        assertTrue(mockGasAccounting.validateBalances());
    }

    function test_contribute() public {
        vm.expectRevert(
            abi.encodeWithSelector(FastLaneErrorsEvents.InvalidExecutionEnvironment.selector, executionEnvironment)
        );
        mockGasAccounting.contribute();

        uint256 contributeValue = 1000;
        deal(executionEnvironment, contributeValue);

        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: contributeValue }();

        assertEq(address(mockGasAccounting).balance, contributeValue);
        assertEq(mockGasAccounting.deposits(), contributeValue);
    }

    function test_borrow() public {
        uint256 borrowedAmount = 5000;

        vm.expectRevert(
            abi.encodeWithSelector(FastLaneErrorsEvents.InvalidExecutionEnvironment.selector, executionEnvironment)
        );
        mockGasAccounting.borrow(borrowedAmount);

        vm.prank(executionEnvironment);
        vm.expectRevert(
            abi.encodeWithSelector(FastLaneErrorsEvents.InsufficientAtlETHBalance.selector, 0, borrowedAmount)
        );
        mockGasAccounting.borrow(borrowedAmount);

        deal(
            address(mockGasAccounting),
            initialClaims + borrowedAmount // claims + amount borrowed
        );

        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(executionEnvironment.balance, borrowedAmount);
    }

    function test_shortfall() public {
        assertEq(mockGasAccounting.shortfall(), initialClaims);

        deal(executionEnvironment, initialClaims);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: initialClaims }();

        assertEq(mockGasAccounting.shortfall(), 0);
    }

    function test_reconcile() public {
        vm.expectRevert(
            abi.encodeWithSelector(FastLaneErrorsEvents.InvalidExecutionEnvironment.selector, executionEnvironment)
        );
        mockGasAccounting.reconcile(makeAddr("wrongExecutionEnvironment"), solverOp.from, 0);

        mockGasAccounting.trySolverLock(solverOp);
        vm.expectRevert(abi.encodeWithSelector(FastLaneErrorsEvents.InvalidSolverFrom.selector, solverOp.from));
        mockGasAccounting.reconcile(executionEnvironment, makeAddr("wrongSolver"), 0);

        vm.expectRevert(abi.encodeWithSelector(FastLaneErrorsEvents.InsufficientTotalBalance.selector, initialClaims));
        mockGasAccounting.reconcile(executionEnvironment, solverOp.from, 0);

        assertEq(mockGasAccounting.solver(), solverOp.from);
        assertTrue(mockGasAccounting.reconcile{ value: initialClaims }(executionEnvironment, solverOp.from, 0));
        assertEq(mockGasAccounting.solver(), mockGasAccounting.SOLVER_FULFILLED());
    }

    function test_assign() public {
        uint256 assignedAmount = 1000;
        uint256 bondedTotalSupplyBefore;
        uint256 depositsBefore;
        uint128 bonded;
        uint128 unbonding;
        uint128 lastAccessedBlock;

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        assertFalse(mockGasAccounting.assign(solverOp.from, 0));
        (, lastAccessedBlock) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint128(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        assertTrue(mockGasAccounting.assign(solverOp.from, assignedAmount));
        (, lastAccessedBlock) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint128(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, 0);
        assertEq(bonded, 0);

        uint256 unbondingAmount = assignedAmount * 2;
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        assertFalse(mockGasAccounting.assign(solverOp.from, assignedAmount));
        (, lastAccessedBlock) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint128(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore - assignedAmount);
        assertEq(mockGasAccounting.deposits(), depositsBefore + assignedAmount);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, unbondingAmount + bonded - assignedAmount);
        assertEq(bonded, 0);

        uint256 bondedAmount = assignedAmount * 3;
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        (, uint128 unbondingBefore) = mockGasAccounting.balanceOf(solverOp.from);
        assertFalse(mockGasAccounting.assign(solverOp.from, assignedAmount));
        (, lastAccessedBlock) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint128(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore - assignedAmount);
        assertEq(mockGasAccounting.deposits(), depositsBefore + assignedAmount);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, unbondingBefore);
        assertEq(bonded, bondedAmount - assignedAmount);

        // Testing uint128 boundary values for casting between uint128 and uint256 in _assign()
        bondedAmount = uint256(type(uint128).max) + 1e18;
        assignedAmount = uint256(type(uint128).max) + 1;
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        (, unbondingBefore) = mockGasAccounting.balanceOf(solverOp.from);
        vm.expectRevert(stdError.arithmeticError);
        mockGasAccounting.assign(solverOp.from, assignedAmount);
        // Check assign reverted with overflow, and accounting values did not change
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);
    }

    function test_credit() public {
        uint256 creditedAmount = 10_000;

        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        (uint128 bondedBefore,) = mockGasAccounting.accessData(solverOp.from);

        mockGasAccounting.credit(solverOp.from, creditedAmount);
        (, uint256 lastAccessedBlock) = mockGasAccounting.accessData(solverOp.from);
        (uint128 bondedAfter,) = mockGasAccounting.accessData(solverOp.from);

        assertEq(lastAccessedBlock, uint128(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore + creditedAmount);
        assertEq(bondedAfter, bondedBefore + uint128(creditedAmount));
    }

    function test_trySolverLock() public {
        assertTrue(mockGasAccounting.trySolverLock(solverOp));

        solverOp.value = 100_000;
        assertFalse(mockGasAccounting.trySolverLock(solverOp));
    }

    function test_releaseSolverLock() public {
        solverOp.data = abi.encodePacked("calldata");
        uint256 calldataCost = (solverOp.data.length * CALLDATA_LENGTH_PREMIUM) + 1;
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 maxGasUsed;
        uint128 bondedBefore;
        uint128 bondedAfter;
        uint256 result;

        // FULL_REFUND
        result = EscrowBits._EXECUTION_REFUND;
        maxGasUsed = gasWaterMark + calldataCost;
        maxGasUsed = (maxGasUsed + ((maxGasUsed * mockGasAccounting.SURCHARGE()) / mockGasAccounting.SURCHARGE_BASE()))
            * tx.gasprice;
        mockGasAccounting.increaseBondedBalance(solverOp.from, maxGasUsed);
        (bondedBefore,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
        (bondedAfter,) = mockGasAccounting.accessData(solverOp.from);
        assertGt(
            bondedBefore - bondedAfter,
            (calldataCost + ((calldataCost * mockGasAccounting.SURCHARGE()) / mockGasAccounting.SURCHARGE_BASE()))
                * tx.gasprice
        ); // Must be greater than calldataCost
        assertLt(bondedBefore - bondedAfter, maxGasUsed); // Must be less than maxGasUsed

        // CALLDATA_REFUND
        result = 1 << uint256(SolverOutcome.InsufficientEscrow);
        maxGasUsed = (
            calldataCost + ((calldataCost * mockGasAccounting.SURCHARGE()) / mockGasAccounting.SURCHARGE_BASE())
        ) * tx.gasprice;
        mockGasAccounting.increaseBondedBalance(solverOp.from, maxGasUsed);
        (bondedBefore,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
        (bondedAfter,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(bondedBefore - bondedAfter, maxGasUsed);

        // NO_USER_REFUND
        result = 1 << uint256(SolverOutcome.InvalidTo);
        (bondedBefore,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
        (bondedAfter,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(bondedBefore, bondedAfter);

        // UncoveredResult
        result = 0;
        vm.expectRevert(FastLaneErrorsEvents.UncoveredResult.selector);
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
    }

    function test_settle() public {
        address bundler = makeAddr("bundler");
        uint128 bondedBefore;
        uint128 bondedAfter;

        vm.expectRevert();
        // This reverts with FastLaneErrorsEvents.InsufficientTotalBalance(shortfall).
        // The shortfall argument can't be reliably calculated in this test, hence
        // we expect a generic revert. Run this test with high verbosity to confirm
        // it reverts with the correct error.
        mockGasAccounting.settle(solverOp.from, bundler);

        // Deficit, but solver has enough balance to cover it
        mockGasAccounting.increaseBondedBalance(solverOp.from, initialClaims);
        (bondedBefore,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.settle(solverOp.from, bundler);
        (bondedAfter,) = mockGasAccounting.accessData(solverOp.from);
        assertLt(bondedAfter, bondedBefore);

        // Surplus, credited to solver's bonded balance
        deal(executionEnvironment, initialClaims);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: initialClaims }();
        (bondedBefore,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.settle(solverOp.from, bundler);
        (bondedAfter,) = mockGasAccounting.accessData(solverOp.from);
        assertGt(bondedAfter, bondedBefore);
    }
}
