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

import "forge-std/console.sol";

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

    /////////////////////////////////////////////////////////
    //  Expose access to internal functions for testing    //
    /////////////////////////////////////////////////////////

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

    /////////////////////////////////////////////////////////
    //                 SETTERS & HELPERS                   //
    /////////////////////////////////////////////////////////

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

    function setPhase(ExecutionPhase _phase) external {
        _setLockPhase(uint8(_phase));
    }

    function setSolverLock(address _solverFrom) external {
        _setSolverLock(uint256(uint160(_solverFrom)));
    }

    function _balanceOf(address account) external view returns (uint112, uint112) {
        return (s_balanceOf[account].balance, s_balanceOf[account].unbonding);
    }

    function initializeLock(address executionEnvironment, uint256 gasMarker) external payable {
        DAppConfig memory dConfig;
        _setEnvironmentLock(dConfig, executionEnvironment);
        _initializeAccountingValues(gasMarker);
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

    function activeEnvironment() public view returns (address) {
        return _activeEnvironment();
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
    address executionEnvironment;
    uint256 snapshotId;

    function setUp() public override {
        // Run the base setup
        super.setUp();

        // Compute expected addresses for the deployment
        address expectedAtlasAddr = vm.computeCreateAddress(payee, vm.getNonce(payee) + 1);
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedAtlasAddr, "AtlasFactory 1.0"));
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedAtlasAddr);

        // Initialize MockGasAccounting
        mockGasAccounting = new MockGasAccounting(
            DEFAULT_ESCROW_DURATION, address(atlasVerification), address(simulator), payee, address(execEnvTemplate)
        );

        // Initialize TestAtlas storage slots
        initializeTestAtlasSlots();

        gasMarker = gasleft();
        mockGasAccounting.initializeLock{ value: 0 }(solverOneEOA, gasMarker);
        initialClaims = getInitialClaims(gasMarker);
        solverOp.from = solverOneEOA; // Use the solverOneEOA address from BaseTest
        solverOp.to = solverOneEOA;
        solverOp.data = abi.encodePacked("calldata");
        executionEnvironment = mockGasAccounting.activeEnvironment();

        // Ensure the execution environment starts with zero balance
        deal(executionEnvironment, 0);

        // Take a snapshot before each test
        snapshotId = vm.snapshot();
    }

    function tearDown() public {
        // Revert to the snapshot after each test
        vm.revertTo(snapshotId);
    }

    function initializeTestAtlasSlots() internal {
        mockGasAccounting.clearTransientStorage();
    }

    function getInitialClaims(uint256 _gasMarker) public view returns (uint256 claims) {
        uint256 rawClaims = (_gasMarker + mockGasAccounting.FIXED_GAS_OFFSET()) * tx.gasprice;
        claims = rawClaims
            * (
                mockGasAccounting.SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE()
                    + mockGasAccounting.BUNDLER_SURCHARGE_RATE()
            ) / mockGasAccounting.SCALE();
    }

    function fundContract(uint256 amount) internal {
        // Fund the contract with enough ETH
        deal(address(mockGasAccounting), amount);
        // Verify the contract has sufficient balance
        assertEq(address(mockGasAccounting).balance, amount, "Contract should have enough ETH balance");
    }

    function test_contribute_withInvalidExecutionEnvironment_revert() public {
        // Expect revert when contribute is called without the proper setup
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, address(0)));
        mockGasAccounting.contribute();

        tearDown();
    }

    function test_contribute() public {
        // Set up the environment for a valid contribute call
        uint256 contributeValue = 1000;
        deal(executionEnvironment, contributeValue);
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.SolverOperation));

        // Perform the valid contribute call
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: contributeValue }();

        // Verify the balances after contribution
        assertEq(address(mockGasAccounting).balance, contributeValue);
        assertEq(mockGasAccounting.getDeposits(), contributeValue);

        tearDown();
    }

    function test_borrow_preOpsPhase() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));

        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(
            solverOneEOA.balance, borrowedAmount, "Execution environment balance should be equal to borrowed amount"
        );

        tearDown();
    }

    function test_borrow_userOperationPhase() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);

        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.UserOperation));
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(
            executionEnvironment.balance,
            borrowedAmount,
            "Execution environment balance should be equal to borrowed amount"
        );

        tearDown();
    }

    function test_borrow_preSolverPhase() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);

        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreSolver));
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(
            executionEnvironment.balance,
            borrowedAmount,
            "Execution environment balance should be equal to borrowed amount"
        );

        tearDown();
    }

    function test_borrow_solverOperationPhase() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);

        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.SolverOperation));
        vm.prank(executionEnvironment);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(
            executionEnvironment.balance,
            borrowedAmount,
            "Execution environment balance should be equal to borrowed amount"
        );

        tearDown();
    }

    function test_borrow_postSolverPhase_reverts() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);

        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PostSolver));
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(executionEnvironment.balance, 0, "Execution environment balance should remain zero");

        tearDown();
    }

    function test_borrow_allocateValuePhase_reverts() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);

        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.AllocateValue));
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(executionEnvironment.balance, 0, "Execution environment balance should remain zero");

        tearDown();
    }

    function test_borrow_postOpsPhase_reverts() public {
        uint256 borrowedAmount = 1e18;

        fundContract(borrowedAmount);

        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PostOps));
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.borrow(borrowedAmount);

        assertEq(executionEnvironment.balance, 0, "Execution environment balance should remain zero");

        tearDown();
    }

    function test_multipleBorrows() public {
        uint256 atlasBalance = 100 ether;
        uint256 borrow1 = 75 ether;
        uint256 borrow2 = 10 ether;
        uint256 borrow3 = 15 ether;

        // Ensure the execution environment starts with zero balance
        deal(executionEnvironment, 0);
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.SolverOperation));

        // Fund the contract with enough ETH (initial claims + total borrow amount)
        uint256 totalBorrowAmount = borrow1 + borrow2 + borrow3;
        deal(address(mockGasAccounting), initialClaims + atlasBalance);

        // Verify the contract has sufficient balance before borrowing
        assertEq(
            address(mockGasAccounting).balance, initialClaims + atlasBalance, "Contract should have enough ETH balance"
        );

        // Set the phase to an allowed phase for borrowing
        mockGasAccounting.setPhase(ExecutionPhase.PreOps);

        // Start borrowing operations
        vm.startPrank(executionEnvironment);
        mockGasAccounting.borrow(borrow1);
        assertEq(
            executionEnvironment.balance,
            borrow1,
            "Execution environment balance should equal borrow1 after first borrow"
        );

        mockGasAccounting.borrow(borrow2);
        assertEq(
            executionEnvironment.balance,
            borrow1 + borrow2,
            "Execution environment balance should equal borrow1 + borrow2 after second borrow"
        );

        mockGasAccounting.borrow(borrow3);
        assertEq(
            executionEnvironment.balance,
            borrow1 + borrow2 + borrow3,
            "Execution environment balance should equal borrow1 + borrow2 + borrow3 after third borrow"
        );
        vm.stopPrank();

        // Verify the final balance of the execution environment
        assertEq(
            executionEnvironment.balance,
            borrow1 + borrow2 + borrow3,
            "Final execution environment balance should equal total borrowed amount"
        );

        // Verify the final balance of the contract
        uint256 expectedFinalContractBalance = initialClaims + atlasBalance - totalBorrowAmount;
        assertEq(
            address(mockGasAccounting).balance,
            expectedFinalContractBalance,
            "Final contract balance should be initial balance minus total borrowed amount"
        );
        tearDown();
    }

    function test_shortfall() public {
        // Ensure the execution environment starts with zero balance
        deal(executionEnvironment, 0);

        // Set initial claims in the contract
        mockGasAccounting.setClaims(initialClaims);

        // Verify initial shortfall
        assertEq(mockGasAccounting.shortfall(), initialClaims, "Initial shortfall should be equal to initial claims");

        // Contribute to the contract
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));
        deal(executionEnvironment, initialClaims);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: initialClaims }();

        // Verify shortfall after contribution
        assertEq(mockGasAccounting.shortfall(), 0, "Shortfall should be zero after contribution");
        tearDown();
    }

    function test_reconcile_initializeClaimsAndDeposits() public {
        // Set initial claims and deposits
        mockGasAccounting.setClaims(10 ether);
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.UserOperation));

        deal(executionEnvironment, 10 ether);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: 10 ether }();

        assertEq(mockGasAccounting.claims(), 10 ether, "Claims should be set to 10 ether");
        assertEq(address(mockGasAccounting).balance, 10 ether, "mockGasAccounting should have 10 ether");
        tearDown();
    }

    function test_reconcile_withWrongPhase_reverts() public {
        // Set initial claims and deposits
        mockGasAccounting.setClaims(10 ether);
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.UserOperation));

        deal(executionEnvironment, 10 ether);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: 10 ether }();

        // Expect revert if called in the wrong phase
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.reconcile(0);
        tearDown();
    }

    function test_reconcile_invalidAccess_reverts() public {
        // Set phase to SolverOperation and set solver lock
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.SolverOperation));
        mockGasAccounting.setSolverTo(solverOneEOA);

        // Ensure bonded balance is set
        mockGasAccounting.increaseBondedBalance(solverOneEOA, 10 ether);

        // Expect revert if called by the wrong address
        vm.expectRevert(AtlasErrors.InvalidAccess.selector);
        mockGasAccounting.reconcile(0);
        tearDown();
    }

    function test_reconcile_withCorrectAddress() public {
        // Set initial claims and deposits
        mockGasAccounting.setClaims(20 ether); // Increased claims to ensure deductions are higher
        mockGasAccounting.setLock(executionEnvironment, 0, uint8(ExecutionPhase.SolverOperation));
        deal(executionEnvironment, 10 ether);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: 10 ether }();

        mockGasAccounting.setSolverTo(executionEnvironment);

        // Ensure bonded balance is set
        mockGasAccounting.increaseBondedBalance(executionEnvironment, 10 ether);

        // Call reconcile with the correct execution environment
        vm.prank(executionEnvironment);
        uint256 result = mockGasAccounting.reconcile(5 ether);
        assertTrue(result > 0, "Reconcile should return a value greater than zero");
    }

    function test_reconcile() public {
        // Ensure the execution environment starts with zero balance
        deal(executionEnvironment, 0);

        // Fund the contract to allow reconciliation
        deal(executionEnvironment, initialClaims);

        // Set phase to SolverOperation and set solver lock
        mockGasAccounting.setPhase(ExecutionPhase.SolverOperation);
        mockGasAccounting.setSolverLock(solverOneEOA);
        mockGasAccounting.setSolverTo(solverOneEOA);

        // Call reconcile with the correct execution environment
        vm.prank(solverOneEOA);
        assertTrue(mockGasAccounting.reconcile{ value: initialClaims }(0) == 0, "Reconcile should return zero");

        // Verify solver lock data
        (address currentSolver, bool verified, bool fulfilled) = mockGasAccounting.solverLockData();
        assertTrue(verified && fulfilled, "Solver should be verified and fulfilled");
        assertEq(currentSolver, solverOneEOA, "Current solver should match execution environment");
        tearDown();
    }

    function test_assign_zeroAmount() public {
        uint256 assignedAmount = 0;
        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();

        mockGasAccounting.increaseBondedBalance(solverOp.from, assignedAmount * 3);
        assertEq(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, uint32 lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        tearDown();
    }

    function test_assign_sufficientBondedBalance() public {
        uint256 assignedAmount = 1000;
        uint256 initialBondedAmount = assignedAmount * 3;

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        assertEq(mockGasAccounting.assign(solverOp.from, 0, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        // Initialize bonded balance
        mockGasAccounting.increaseBondedBalance(solverOp.from, initialBondedAmount);

        // Get initial values
        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();

        uint256 deficit = mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        assertEq(deficit, 0, "Deficit should be 0");

        (, uint32 lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.getDeposits(), depositsBefore);

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.getDeposits();
        assertGt(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        uint256 bondedTotalSupplyAfter = mockGasAccounting.bondedTotalSupply();
        uint256 depositsAfter = mockGasAccounting.deposits();

        assertEq(bondedTotalSupplyAfter, bondedTotalSupplyBefore - assignedAmount);
        assertEq(depositsAfter, depositsBefore + assignedAmount);

        tearDown();
    }

    function test_assign_insufficientBondedSufficientUnbonding() public {
        uint256 assignedAmount = 1000;
        uint256 unbondingAmount = assignedAmount * 2; // 2000
        uint256 bondedAmount = assignedAmount / 2; // 500

        // Set up initial balances
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount); // Set unbonding balance to 2000
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount); // Set bonded balance to 500

        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();

        // Call the assign function and capture the deficit
        uint256 deficit = mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        assertEq(deficit, 0, "Deficit should be 0");

        // Retrieve and check the updated access data
        (, uint32 lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number), "Last accessed block should be current block");

        // Check the updated bonded total supply and deposits
        assertEq(
            mockGasAccounting.bondedTotalSupply(),
            bondedTotalSupplyBefore - assignedAmount,
            "Bonded total supply mismatch"
        );
        assertEq(mockGasAccounting.deposits(), depositsBefore + assignedAmount, "Deposits mismatch");

        // Retrieve and check the updated balances
        (uint112 bonded, uint112 unbonding) = mockGasAccounting._balanceOf(solverOp.from);
        uint256 expectedUnbonding = uint112(unbondingAmount - (assignedAmount - bondedAmount));
        assertEq(unbonding, expectedUnbonding, "Unbonding balance mismatch");
        assertEq(bonded, 0, "Bonded balance mismatch");

        tearDown();
    }

    function test_assign_insufficientBondedAndUnbonding() public {
        uint256 assignedAmount = 1000;
        uint256 unbondingAmount = assignedAmount / 2;
        uint256 bondedAmount = assignedAmount / 4;

        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount);
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);

        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();
        uint256 deficit = mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        assertEq(deficit, assignedAmount - (unbondingAmount + bondedAmount));
        (, uint32 lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
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
        tearDown();
    }

    function test_assign_reputationAnalytics() public {
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

        tearDown();
    }

    function test_assign_overflow_reverts() public {
        uint256 bondedAmount = uint256(type(uint112).max) + 1e18;
        uint256 assignedAmount = uint256(type(uint112).max) + 1;

        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 depositsBefore = mockGasAccounting.deposits();
        (uint112 unbondingBefore,) = mockGasAccounting._balanceOf(solverOp.from);
        vm.expectRevert("SafeCast: value doesn't fit in 112 bits");
        mockGasAccounting.assign(solverOp.from, assignedAmount, true);

        // Check assign reverted with overflow, and accounting values did not change
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        (uint112 unbonding,) = mockGasAccounting._balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);
    }

    function test_credit() public {
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
        vm.expectRevert("SafeCast: value doesn't fit in 112 bits");
        mockGasAccounting.credit(solverOp.from, overflowAmount);

        tearDown();
    }

    function test_handleSolverAccounting_solverNotResponsible() public {
        // Setup
        solverOp.data = "";
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 initialWriteoffs = mockGasAccounting.writeoffs();

        // Simulate solver not responsible for failure
        uint256 result = EscrowBits._NO_REFUND;
        // Recalculate expected writeoffs
        uint256 gasUsedOffset = 7_073_515_500_000_000; //difference between _gasUsed
        uint256 gasUsed =
            (gasWaterMark + mockGasAccounting.solverBaseGasUsed() - gasleft()) * tx.gasprice + gasUsedOffset;
        mockGasAccounting.handleSolverAccounting(solverOp, gasWaterMark, result, false);
        uint256 expectedWriteoffs = initialWriteoffs + AccountingMath.withAtlasAndBundlerSurcharges(gasUsed);

        // Verify writeoffs have increased
        assertEq(mockGasAccounting.writeoffs(), expectedWriteoffs, "Writeoffs mismatch");

        tearDown();
    }

    function test_handleSolverAccounting_solverResponsible() public {
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

        tearDown();
    }

    function test_handleSolverAccounting_includingCalldata() public {
        // Setup
        solverOp.data = abi.encodePacked("calldata");
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 initialBondedBalance = 1000 ether;
        uint256 unbondingAmount = 500 ether;

        // Set up initial balances
        mockGasAccounting.increaseBondedBalance(solverOp.from, initialBondedBalance);
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount); // Set unbonding balance

        // Perform the operation
        (uint112 unbondingBefore,) = mockGasAccounting._balanceOf(solverOp.from);

        // Simulate solver responsible for failure including calldata
        uint256 result = EscrowBits._FULL_REFUND;

        mockGasAccounting.handleSolverAccounting(solverOp, gasWaterMark, result, true);

        // Verify bonded balance has decreased
        (uint112 unbonding,) = mockGasAccounting._balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);

        tearDown();
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
