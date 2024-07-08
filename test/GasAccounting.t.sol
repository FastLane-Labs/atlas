// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { GasAccounting } from "src/contracts/atlas/GasAccounting.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";
import "src/contracts/libraries/AccountingMath.sol";
import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/ConfigTypes.sol";

import { ExecutionEnvironment } from "src/contracts/common/ExecutionEnvironment.sol";

import { TestAtlas } from "test/base/TestAtlas.sol";
import { BaseTest } from "test/base/BaseTest.t.sol";

contract MockGasAccounting is TestAtlas, BaseTest {
    uint256 public constant MOCK_SOLVER_GAS_LIMIT = 500_000;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient,
        address _l2GasCalculator
    )
        GasAccounting(_escrowDuration, _verification, _simulator, _surchargeRecipient, _l2GasCalculator)
    { }

    function _balanceOf(address account) external view returns (uint112, uint112) {
        return (s_balanceOf[account].balance, s_balanceOf[account].unbonding);
    }

    function initializeLock(address executionEnvironment, uint256 gasMarker, uint256 userOpValue) external payable {
        DAppConfig memory dConfig;
        _setEnvironmentLock(dConfig, executionEnvironment);
        _initializeAccountingValues(gasMarker);
    }

    function setPhase(ExecutionPhase _phase) external {
        _setLockPhase(uint8(_phase));
    }

    function setSolverLock(address _solverFrom) external {
        _setSolverLock(uint256(uint160(_solverFrom)));
    }

    function assign(address owner, uint256 value, bool solverWon) external returns (uint256) {
        return _assign(owner, value, value, solverWon);
    }

    function credit(address owner, uint256 value) external {
        _credit(owner, value, value);
    }

    function handleSolverAccounting(
        SolverOperation calldata solverOp,
        uint256 gasWaterMark,
        uint256 result,
        bool includeCalldata
    )
        external
    {
        _handleSolverAccounting(solverOp, gasWaterMark, result, includeCalldata);
    }

    function settle(address winningSolver, address bundler) external returns (uint256, uint256) {
        Context memory ctx = buildContext(bundler, true, true, 0, 1);

        return _settle(ctx, MOCK_SOLVER_GAS_LIMIT);
    }

    function buildContext(
        address bundler,
        bool solverSuccessful,
        bool paymentsSuccessful,
        uint256 winningSolverIndex,
        uint256 solverCount
    )
        public
        view
        returns (Context memory ctx)
    {
        ctx = Context({
            executionEnvironment: _activeEnvironment(),
            userOpHash: bytes32(0),
            bundler: bundler,
            solverSuccessful: solverSuccessful,
            paymentsSuccessful: paymentsSuccessful,
            solverIndex: uint8(winningSolverIndex),
            solverCount: uint8(solverCount),
            phase: uint8(ExecutionPhase.PostOps),
            solverOutcome: 0,
            bidFind: false,
            isSimulation: false,
            callDepth: 0
        });
    }

    function increaseBondedBalance(address account, uint256 amount) external {
        deal(address(this), amount);
        S_accessData[account].bonded += uint112(amount);
        S_bondedTotalSupply += amount;
    }

    function increaseUnbondingBalance(address account, uint256 amount) external {
        deal(address(this), amount);
        s_balanceOf[account].unbonding += uint112(amount);
        S_bondedTotalSupply += amount;
    }

    function calldataLengthPremium() external pure returns (uint256) {
        return _CALLDATA_LENGTH_PREMIUM;
    }

    // View functions

    function getClaims() external view returns (uint256) {
        return claims();
    }

    function getFees() external view returns (uint256) {
        return fees();
    }

    function getWriteoffs() external view returns (uint256) {
        return writeoffs();
    }

    function getWithdrawals() external view returns (uint256) {
        return withdrawals();
    }

    function getDeposits() external view returns (uint256) {
        return deposits();
    }

    function getCalldataCost(uint256 length) external view returns (uint256) {
        return _getCalldataCost(length);
    }
}

contract MockGasCalculator is IL2GasCalculator, Test {
    function getCalldataCost(uint256 length) external view returns (uint256 calldataCostETH) {
        calldataCostETH = length * 16;
    }

    function initialGasUsed(uint256 calldataLength) external view returns (uint256 gasUsed) {
        gasUsed = calldataLength * 16;
    }
}

contract GasAccountingTest is AtlasConstants, BaseTes {
    MockGasAccounting public mockGasAccounting;
    uint256 gasMarker;
    uint256 initialClaims;
    SolverOperation solverOp;
    address executionEnvironment = makeAddr("executionEnvironment");

    function setUp() public override {
        // Run the base setup
        super.setUp();

        mockGasAccounting = new MockGasAccounting(
            DEFAULT_ESCROW_DURATION,
            address(atlasVerification),
            address(simulator),
            payee,
            address(new ExecutionEnvironment(address(atlas)))
        );

        gasMarker = gasleft();
        mockGasAccounting.initializeLock{ value: 0 }(executionEnvironment, gasMarker, 0);
        initialClaims = getInitialClaims(gasMarker);
        solverOp.from = makeAddr("solver");
        solverOp.data = abi.encodePacked("calldata");
        // Initialize TestAtlas storage slots
        initializeTestAtlasSlots();
    }

    function initializeTestAtlasSlots() internal {
        mockGasAccounting.clearTransientStorage();
        mockGasAccounting.setLock(Lock(address(0), 0, 0));
        mockGasAccounting.setSolverLock(0);
        mockGasAccounting.setSolverTo(address(0));
        mockGasAccounting.setClaims(0);
        mockGasAccounting.setFees(0);
        mockGasAccounting.setWriteoffs(0);
        mockGasAccounting.setWithdrawals(0);
        mockGasAccounting.setDeposits(0);
    }

    function getInitialClaims(uint256 _gasMarker) public view returns (uint256 claims) {
        uint256 rawClaims = (_gasMarker + mockGasAccounting.FIXED_GAS_OFFSET()) * tx.gasprice;
        claims = rawClaims
            * (
                mockGasAccounting.SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE()
                    + mockGasAccounting.BUNDLER_SURCHARGE_RATE()
            ) / mockGasAccounting.SCALE();
    }

    function test_contribute() public {
        vm.skip(true);
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, executionEnvironment));
        mockGasAccounting.contribute();

        uint256 contributeValue = 1000;
        deal(executionEnvironment, contributeValue);

        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: contributeValue }();

        assertEq(address(mockGasAccounting).balance, contributeValue);
        assertEq(mockGasAccounting.getDeposits(), contributeValue);
    }

    function test_borrow() public {
        vm.skip(true);
        uint256 borrowedAmount = 5000;

        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, executionEnvironment));
        mockGasAccounting.borrow(borrowedAmount);

        vm.prank(executionEnvironment);
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InsufficientAtlETHBalance.selector, 0, borrowedAmount));
        mockGasAccounting.borrow(borrowedAmount);

        deal(
            address(mockGasAccounting),
            initialClaims + borrowedAmount // claims + amount borrowed
        );

        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(executionEnvironment.balance, borrowedAmount);
    }

    function test_borrow_phasesEnforced() public {
        vm.skip(true);
        uint256 borrowedAmount = 1e18;
        deal(address(mockGasAccounting), borrowedAmount);
        assertEq(executionEnvironment.balance, 0, "EE should start with 0 ETH");
        uint256 startState = vm.snapshot();

        // Allowed borrowed phases: PreOps, UserOperation, PreSolver, SolverOperations

        mockGasAccounting.setPhase(ExecutionPhase.PreOps);
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, borrowedAmount);
        vm.revertTo(startState);

        mockGasAccounting.setPhase(ExecutionPhase.UserOperation);
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, borrowedAmount);
        vm.revertTo(startState);

        mockGasAccounting.setPhase(ExecutionPhase.PreSolver);
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, borrowedAmount);
        vm.revertTo(startState);

        mockGasAccounting.setPhase(ExecutionPhase.SolverOperation);
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, borrowedAmount);
        vm.revertTo(startState);

        // Disallowed borrowed phases: PostSolver, AllocateValue, PostOps

        mockGasAccounting.setPhase(ExecutionPhase.PostSolver);
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, 0);
        vm.revertTo(startState);

        mockGasAccounting.setPhase(ExecutionPhase.AllocateValue);
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, 0);
        vm.revertTo(startState);

        mockGasAccounting.setPhase(ExecutionPhase.PostOps);
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.borrow(borrowedAmount);
        assertEq(executionEnvironment.balance, 0);
        vm.revertTo(startState);
    }

    function test_multipleBorrows() public {
        vm.skip(true);
        uint256 atlasBalance = 100 ether;
        uint256 borrow1 = 75 ether;
        uint256 borrow2 = 10 ether;
        uint256 borrow3 = 15 ether;

        deal(address(mockGasAccounting), initialClaims + atlasBalance);

        vm.startPrank(executionEnvironment);
        mockGasAccounting.borrow(borrow1);
        mockGasAccounting.borrow(borrow2);
        mockGasAccounting.borrow(borrow3);
        vm.stopPrank();

        assertEq(executionEnvironment.balance, borrow1 + borrow2 + borrow3);
    }

    function test_shortfall() public {
        vm.skip(true);
        assertEq(mockGasAccounting.shortfall(), initialClaims);

        deal(executionEnvironment, initialClaims);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: initialClaims }();

        assertEq(mockGasAccounting.shortfall(), 0);
    }

    function test_reconcileFail() public {
        vm.skip(true);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.reconcile(0);

        mockGasAccounting.setPhase(ExecutionPhase.SolverOperation);
        mockGasAccounting.setSolverLock(solverOp.from);

        assertTrue(mockGasAccounting.reconcile(0) > 0);
    }

    function test_reconcile() public {
        vm.skip(true);
        mockGasAccounting.setPhase(ExecutionPhase.SolverOperation);
        mockGasAccounting.setSolverLock(solverOp.from);
        assertTrue(mockGasAccounting.reconcile{ value: initialClaims }(0) == 0);
        (address currentSolver, bool verified, bool fulfilled) = mockGasAccounting.solverLockData();
        assertTrue(verified && fulfilled);
        assertEq(currentSolver, solverOp.from);
    }

    function test_assign_zeroAmount() public {
        uint256 snapshotId = vm.snapshot();

        uint256 assignedAmount = 0;
        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();

        mockGasAccounting.increaseBondedBalance(solverOp.from, assignedAmount * 3);
        assertEq(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, uint32 lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);

        vm.revertTo(snapshotId);
    }

    function test_assign_sufficientBondedBalance() public {
        uint256 snapshotId = vm.snapshot();

        uint256 assignedAmount = 1000;
        uint256 initialBondedAmount = assignedAmount * 3;

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        assertEq(mockGasAccounting.assign(solverOp.from, 0, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.getDeposits(), depositsBefore);

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        assertGt(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.getDeposits(), depositsBefore);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, 0);
        assertEq(bonded, 0);

        uint256 unbondingAmount = assignedAmount * 2;
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        assertEq(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore - assignedAmount);
        assertEq(mockGasAccounting.getDeposits(), depositsBefore + assignedAmount);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, unbondingAmount + bonded - assignedAmount);
        assertEq(bonded, 0);

        uint256 bondedAmount = assignedAmount * 3;
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        (, uint112 unbondingBefore) = mockGasAccounting.balanceOf(solverOp.from);
        assertEq(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore - assignedAmount);
        assertEq(mockGasAccounting.getDeposits(), depositsBefore + assignedAmount);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, unbondingBefore);
        assertEq(bonded, bondedAmount - assignedAmount);

        // Testing uint112 boundary values for casting between uint112 and uint256 in _assign()
        bondedAmount = uint256(type(uint112).max) + 1e18;
        assignedAmount = uint256(type(uint112).max) + 1;
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        (, unbondingBefore) = mockGasAccounting.balanceOf(solverOp.from);
        vm.expectRevert(AtlasErrors.ValueTooLarge.selector);
        mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        // Check assign reverted with overflow, and accounting values did not change
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.getDeposits(), depositsBefore);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);
    }

    function test_assign_reputationAnalytics() public {
        uint256 snapshotId = vm.snapshot();

        uint256 gasUsedDecimalsToDrop = 1000;
        uint256 assignedAmount = 1_234_567;
        uint24 auctionWins;
        uint24 auctionFails;
        uint64 totalGasUsed;

        mockGasAccounting.increaseBondedBalance(solverOp.from, 100e18);
        (,, auctionWins, auctionFails, totalGasUsed) = mockGasAccounting.accessData(solverOp.from);
        assertEq(auctionWins, 0, "auctionWins should start at 0");
        assertEq(auctionFails, 0, "auctionFails should start at 0");
        assertEq(totalGasUsed, 0, "totalGasUsed should start at 0");

        mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        uint256 expectedGasUsed = assignedAmount / gasUsedDecimalsToDrop;

        (,, auctionWins, auctionFails, totalGasUsed) = mockGasAccounting.accessData(solverOp.from);
        assertEq(auctionWins, 1, "auctionWins should be incremented by 1");
        assertEq(auctionFails, 0, "auctionFails should remain at 0");
        assertEq(totalGasUsed, expectedGasUsed, "totalGasUsed not as expected");

        mockGasAccounting.assign(solverOp.from, assignedAmount, false);
        expectedGasUsed += assignedAmount / gasUsedDecimalsToDrop;

        (,, auctionWins, auctionFails, totalGasUsed) = mockGasAccounting.accessData(solverOp.from);
        assertEq(auctionWins, 1, "auctionWins should remain at 1");
        assertEq(auctionFails, 1, "auctionFails should be incremented by 1");
        assertEq(totalGasUsed, expectedGasUsed, "totalGasUsed not as expected");

        // Check (type(uint64).max + 2) * gasUsedDecimalsToDrop
        // Should NOT overflow but rather increase totalGasUsed by 1
        // Because uint64() cast takes first 64 bits which only include the 1
        // And exclude (type(uint64).max + 1) * gasUsedDecimalsToDrop hex digits
        // NOTE: This truncation only happens at values > 1.844e22 which is unrealistic for gas spent
        uint256 largeAmountOfGas = (uint256(type(uint64).max) + 2) * gasUsedDecimalsToDrop;

        mockGasAccounting.increaseBondedBalance(address(12_345), 1_000_000e18);
        mockGasAccounting.assign(address(12_345), largeAmountOfGas, false);

        (,,,, totalGasUsed) = mockGasAccounting.accessData(address(12_345));
        assertEq(totalGasUsed, 1, "totalGasUsed should be 1");

        vm.revertTo(snapshotId);
    }

    function test_assign_overflow_reverts() public {
        uint256 snapshotId = vm.snapshot();

        uint256 bondedAmount = uint256(type(uint112).max) + 1e18;
        uint256 assignedAmount = uint256(type(uint112).max) + 1;

        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();
        (uint112 unbondingBefore,) = mockGasAccounting._balanceOf(solverOp.from);
        vm.expectRevert(AtlasErrors.ValueTooLarge.selector);
        mockGasAccounting.assign(solverOp.from, assignedAmount, true);

        // Check assign reverted with overflow, and accounting values did not change
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        (uint112 unbonding,) = mockGasAccounting._balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);

        vm.revertTo(snapshotId);
    }

    function test_credit() public {
        uint256 snapshotId = vm.snapshot();
        uint256 creditedAmount = 10_000;
        uint256 lastAccessedBlock;

        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 withdrawalsBefore = mockGasAccounting.getWithdrawals();
        (uint112 bondedBefore,,,,) = mockGasAccounting.accessData(solverOp.from);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, 0);

        mockGasAccounting.credit(solverOp.from, creditedAmount);

        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        (uint112 bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);

        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore + creditedAmount);
        assertEq(bondedAfter, bondedBefore + uint112(creditedAmount));
        assertEq(mockGasAccounting.getWithdrawals(), withdrawalsBefore + creditedAmount);

        // Testing uint112 boundary values for casting from uint256 to uint112 in _credit()
        uint256 overflowAmount = uint256(type(uint112).max) + 1;
        vm.expectRevert(AtlasErrors.ValueTooLarge.selector);
        mockGasAccounting.credit(solverOp.from, overflowAmount);
        vm.revertTo(snapshotId);
    }

    function test_handleSolverAccounting_solverNotResponsible() public {
        uint256 snapshotId = vm.snapshot();

        // Setup
        solverOp.data = "";
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 initialWriteoffs = mockGasAccounting.writeoffs();

        // Simulate solver not responsible for failure
        uint256 result = EscrowBits._NO_REFUND;

        // Recalculate expected writeoffs
        uint256 _gasUsed = 7_094_964_000_000_000; // gas used

        mockGasAccounting.handleSolverAccounting(solverOp, gasWaterMark, result, false);

        uint256 expectedWriteoffs = initialWriteoffs + AccountingMath.withAtlasAndBundlerSurcharges(_gasUsed);

        // Verify writeoffs have increased
        assertEq(mockGasAccounting.writeoffs(), expectedWriteoffs, "Writeoffs mismatch");

        vm.revertTo(snapshotId);
    }

    function test_handleSolverAccounting_solverResponsible() public {
        uint256 snapshotId = vm.snapshot();

        // Setup
        solverOp.data = ""; // no calldata
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 initialBondedBalance = 1000 ether;
        uint256 unbondingAmount = 500 ether;

        // Set up initial balances
        mockGasAccounting.increaseBondedBalance(solverOp.from, initialBondedBalance);
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount); // Set unbonding balance

        // Simulate solver responsible for failure
        uint256 result = EscrowBits._FULL_REFUND;

        // Perform the operation
        (uint112 unbondingBefore,) = mockGasAccounting._balanceOf(solverOp.from);

        mockGasAccounting.handleSolverAccounting(solverOp, gasWaterMark, result, false);

        // Verify bonded balance has decreased
        (uint112 unbonding,) = mockGasAccounting._balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);

        vm.revertTo(snapshotId);
    }

    function test_handleSolverAccounting_includingCalldata() public {
        uint256 snapshotId = vm.snapshot();

        // Setup
        solverOp.data = abi.encodePacked("calldata");
        uint256 calldataCost = (solverOp.data.length * mockGasAccounting.calldataLengthPremium()) + 1;
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 initialBondedBalance = 1000 ether;
        uint256 unbondingAmount = 500 ether;
        uint256 initialWriteoffs = mockGasAccounting.writeoffs();

        // Set up initial balances
        mockGasAccounting.increaseBondedBalance(solverOp.from, initialBondedBalance);
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount); // Set unbonding balance

        // Perform the operation
        (uint112 unbondingBefore,) = mockGasAccounting._balanceOf(solverOp.from);

        // Simulate solver responsible for failure including calldata
        uint256 result = EscrowBits._FULL_REFUND;

        mockGasAccounting.handleSolverAccounting(solverOp, gasWaterMark, result, true);

        (uint112 bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);
        uint256 gasUsed = 7_200_705_000_000_000 + calldataCost;

        uint256 expectedWriteoffs = initialWriteoffs + AccountingMath.withAtlasAndBundlerSurcharges(gasUsed);

        // Verify bonded balance has decreased
        (uint112 unbonding,) = mockGasAccounting._balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);

        vm.revertTo(snapshotId);
    }

    function test_settle() public {
        // FIXME: fix before merging spearbit-reaudit branch
        vm.skip(true);

        address bundler = makeAddr("bundler");
        uint112 bondedBefore;
        uint112 bondedAfter;

        vm.expectRevert();
        // This reverts with AtlasErrors.InsufficientTotalBalance(shortfall).
        // The shortfall argument can't be reliably calculated in this test, hence
        // we expect a generic revert. Run this test with high verbosity to confirm
        // it reverts with the correct error.
        mockGasAccounting.settle(solverOp.from, bundler);

        // Deficit, but solver has enough balance to cover it
        mockGasAccounting.increaseBondedBalance(solverOp.from, initialClaims);
        (bondedBefore,,,,) = mockGasAccounting.accessData(solverOp.from);
        
        mockGasAccounting.setSolverLock(solverOp.from);

        mockGasAccounting.settle(solverOp.from, bundler);
        (bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertLt(bondedAfter, bondedBefore);

        // Surplus, credited to solver's bonded balance
        deal(executionEnvironment, initialClaims);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: initialClaims }();
        (bondedBefore,,,,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.settle(solverOp.from, bundler);
        (bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertGt(bondedAfter, bondedBefore);
    }

    function test_l2GasCalculatorCall() public {
        IL2GasCalculator gasCalculator = new MockGasCalculator();
        MockGasAccounting l2GasAccounting = new MockGasAccounting(0, address(0), address(0), address(0), address(gasCalculator));
    
        assertEq(l2GasAccounting.getCalldataCost(100), (100 + _SOLVER_OP_BASE_CALLDATA) * 16);
    }

    // function test_bundlerReimbursement() public {
    //     initEscrowLock(gasMarker * tx.gasprice * 2);

    //     // The bundler is being reimbursed for the gas used between 2 gas markers,
    //     // the first one is as the very beginning of metacall, and passed to _setAtlasLock(),
    //     // the second one is in _settle().

    //     // First gas marker, saved as `rawClaims` in _setAtlasLock()
    //     uint256 rawClaims = (gasMarker + mockGasAccounting.FIXED_GAS_OFFSET()) * tx.gasprice;

    //     // Revert calculations to reach the second gas marker value in _settle()
    //     (uint256 claimsPaidToBundler, uint256 netGasSurcharge) = mockGasAccounting.settle(solverOp.from, makeAddr("bundler"));
    //     uint256 settleGasRemainder = initialClaims - (claimsPaidToBundler + netGasSurcharge);
    //     settleGasRemainder = settleGasRemainder * mockGasAccounting.SCALE() / (mockGasAccounting.SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE());

    //     // The bundler must be repaid the gas cost between the 2 markers
    //     uint256 diff = rawClaims - settleGasRemainder;
    //     assertEq(diff, claimsPaidToBundler);
    // }
}
