// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { GasAccounting } from "src/contracts/atlas/GasAccounting.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";

import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/ConfigTypes.sol";

contract MockGasAccounting is GasAccounting, Test {
    uint256 public constant MOCK_SOLVER_GAS_LIMIT = 500_000;
    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        GasAccounting(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    function balanceOf(address account) external view returns (uint112, uint112) {
        return (s_balanceOf[account].balance, s_balanceOf[account].unbonding);
    }

    function initializeLock(address executionEnvironment, uint256 gasMarker, uint256 userOpValue) external payable {
        DAppConfig memory dConfig;
        _setEnvironmentLock(dConfig, executionEnvironment);
        _initializeAccountingValues(gasMarker);
    }

    function setPhase(ExecutionPhase _phase) external {
        T_lock.phase = uint8(_phase);
    }

    function setSolverLock(address _solverFrom) external {
        T_solverLock = uint256(uint160(_solverFrom));
    }

    function assign(address owner, uint256 value, bool solverWon) external returns (uint256) {
        return _assign(owner, value, solverWon);
    }

    function credit(address owner, uint256 value) external {
        _credit(owner, value);
    }

    function releaseSolverLock(SolverOperation calldata solverOp, uint256 gasWaterMark, uint256 result) external {
        _handleSolverAccounting(solverOp, gasWaterMark, result, true);
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
    ) public view returns (Context memory ctx) {
        ctx = Context({
            executionEnvironment: T_lock.activeEnvironment,
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
}

contract GasAccountingTest is Test {
    MockGasAccounting public mockGasAccounting;
    address executionEnvironment = makeAddr("executionEnvironment");

    uint256 gasMarker;
    uint256 initialClaims;
    SolverOperation solverOp;

    function setUp() public {
        mockGasAccounting = new MockGasAccounting(0, address(0), address(0), address(0));
        uint256 _gasMarker = gasleft();

        mockGasAccounting.initializeLock(executionEnvironment, _gasMarker, 0);

        initialClaims = getInitialClaims(_gasMarker);
        solverOp.from = makeAddr("solver");
    }

    function getInitialClaims(uint256 _gasMarker) public view returns (uint256 claims) {
        uint256 rawClaims = (_gasMarker + mockGasAccounting.FIXED_GAS_OFFSET()) * tx.gasprice;
        claims = rawClaims * (
            mockGasAccounting.SURCHARGE_SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE() + mockGasAccounting.BUNDLER_SURCHARGE_RATE()
        ) / mockGasAccounting.SURCHARGE_SCALE();
    }

    function initEscrowLock(uint256 metacallValue) public {
        mockGasAccounting.initializeLock{value: metacallValue}(executionEnvironment, gasMarker, 0);
        uint256 rawClaims = (gasMarker + mockGasAccounting.FIXED_GAS_OFFSET()) * tx.gasprice;
        initialClaims = rawClaims * (
            mockGasAccounting.SURCHARGE_SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE() + mockGasAccounting.BUNDLER_SURCHARGE_RATE()
        ) / mockGasAccounting.SURCHARGE_SCALE();
    }

    function test_contribute() public {
        vm.expectRevert(
            abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, executionEnvironment)
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
            abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, executionEnvironment)
        );
        mockGasAccounting.borrow(borrowedAmount);

        vm.prank(executionEnvironment);
        vm.expectRevert(
            abi.encodeWithSelector(AtlasErrors.InsufficientAtlETHBalance.selector, 0, borrowedAmount)
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

    function test_borrow_phasesEnforced() public {
        // borrow should revert if called in or after PostSolver phase

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
        assertEq(mockGasAccounting.shortfall(), initialClaims);

        deal(executionEnvironment, initialClaims);
        vm.prank(executionEnvironment);
        mockGasAccounting.contribute{ value: initialClaims }();

        assertEq(mockGasAccounting.shortfall(), 0);
    }

    function test_reconcileFail() public {
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        mockGasAccounting.reconcile(0);

        mockGasAccounting.setPhase(ExecutionPhase.SolverOperation);
        mockGasAccounting.setSolverLock(solverOp.from);

        assertTrue(mockGasAccounting.reconcile(0) > 0);
    }

    function test_reconcile() public {
        mockGasAccounting.setPhase(ExecutionPhase.SolverOperation);
        mockGasAccounting.setSolverLock(solverOp.from);
        assertTrue(mockGasAccounting.reconcile{ value: initialClaims }(0) == 0);
        (address currentSolver, bool verified, bool fulfilled) = mockGasAccounting.solverLockData();
        assertTrue(verified && fulfilled);
        assertEq(currentSolver, solverOp.from);
        assertEq(mockGasAccounting.solver(), solverOp.from);
    }

    function test_assign() public {
        uint256 assignedAmount = 1000;
        uint256 bondedTotalSupplyBefore;
        uint256 depositsBefore;
        uint112 bonded;
        uint112 unbonding;
        uint32 lastAccessedBlock;

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        assertEq(mockGasAccounting.assign(solverOp.from, 0, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);

        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        assertGt(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, 0);
        assertEq(bonded, 0);

        uint256 unbondingAmount = assignedAmount * 2;
        mockGasAccounting.increaseUnbondingBalance(solverOp.from, unbondingAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        assertEq(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore - assignedAmount);
        assertEq(mockGasAccounting.deposits(), depositsBefore + assignedAmount);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, unbondingAmount + bonded - assignedAmount);
        assertEq(bonded, 0);

        uint256 bondedAmount = assignedAmount * 3;
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        (, uint112 unbondingBefore) = mockGasAccounting.balanceOf(solverOp.from);
        assertEq(mockGasAccounting.assign(solverOp.from, assignedAmount, true), 0);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore - assignedAmount);
        assertEq(mockGasAccounting.deposits(), depositsBefore + assignedAmount);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        (bonded,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(unbonding, unbondingBefore);
        assertEq(bonded, bondedAmount - assignedAmount);

        // Testing uint112 boundary values for casting between uint112 and uint256 in _assign()
        bondedAmount = uint256(type(uint112).max) + 1e18;
        assignedAmount = uint256(type(uint112).max) + 1;
        mockGasAccounting.increaseBondedBalance(solverOp.from, bondedAmount);
        bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        depositsBefore = mockGasAccounting.deposits();
        (, unbondingBefore) = mockGasAccounting.balanceOf(solverOp.from);
        vm.expectRevert(AtlasErrors.ValueTooLarge.selector);
        mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        // Check assign reverted with overflow, and accounting values did not change
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore);
        assertEq(mockGasAccounting.deposits(), depositsBefore);
        (, unbonding) = mockGasAccounting.balanceOf(solverOp.from);
        assertEq(unbonding, unbondingBefore);
    }

    function test_assign_reputation_analytics() public {
        uint256 gasUsedDecimalsToDrop = 1000; // This should be same value as in Storage.sol
        uint256 assignedAmount = 1_234_567;
        uint24 auctionWins;
        uint24 auctionFails;
        uint64 totalGasUsed;

        mockGasAccounting.increaseBondedBalance(solverOp.from, 100e18);
        (,,auctionWins,auctionFails,totalGasUsed) = mockGasAccounting.accessData(solverOp.from);
        assertEq(auctionWins, 0, "auctionWins should start at 0");
        assertEq(auctionFails, 0, "auctionFails should start at 0");
        assertEq(totalGasUsed, 0, "totalGasUsed should start at 0");

        mockGasAccounting.assign(solverOp.from, assignedAmount, true);
        uint256 expectedGasUsed = assignedAmount / gasUsedDecimalsToDrop;
            
        (,,auctionWins,auctionFails,totalGasUsed) = mockGasAccounting.accessData(solverOp.from);
        assertEq(auctionWins, 1, "auctionWins should be incremented by 1");
        assertEq(auctionFails, 0, "auctionFails should remain at 0");
        assertEq(totalGasUsed, expectedGasUsed, "totalGasUsed not as expected");

        mockGasAccounting.assign(solverOp.from, assignedAmount, false);
        expectedGasUsed += assignedAmount / gasUsedDecimalsToDrop;

        (,,auctionWins,auctionFails,totalGasUsed) = mockGasAccounting.accessData(solverOp.from);
        assertEq(auctionWins, 1, "auctionWins should remain at 1");
        assertEq(auctionFails, 1, "auctionFails should be incremented by 1");
        assertEq(totalGasUsed, expectedGasUsed, "totalGasUsed not as expected");

        // Check (type(uint64).max + 2) * gasUsedDecimalsToDrop
        // Should NOT overflow but rather increase totalGasUsed by 1
        // Because uint64() cast takes first 64 bits which only include the 1
        // And exclude (type(uint64).max + 1) * gasUsedDecimalsToDrop hex digits
        // NOTE: This truncation only happens at values > 1.844e22 which is unrealistic for gas spent
        uint256 largeAmountOfGas = (uint256(type(uint64).max) + 2) * gasUsedDecimalsToDrop;

        mockGasAccounting.increaseBondedBalance(address(12345), 1000000e18);
        mockGasAccounting.assign(address(12345), largeAmountOfGas, false);

        (,,,,totalGasUsed) = mockGasAccounting.accessData(address(12345));
        assertEq(totalGasUsed, 1, "totalGasUsed should be 1");
    }

    function test_credit() public {
        uint256 creditedAmount = 10_000;
        uint256 lastAccessedBlock;

        uint256 bondedTotalSupplyBefore = mockGasAccounting.bondedTotalSupply();
        uint256 withdrawalsBefore = mockGasAccounting.withdrawals();
        (uint112 bondedBefore,,,,) = mockGasAccounting.accessData(solverOp.from);
        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(lastAccessedBlock, 0);

        mockGasAccounting.credit(solverOp.from, creditedAmount);

        (, lastAccessedBlock,,,) = mockGasAccounting.accessData(solverOp.from);
        (uint112 bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);

        assertEq(lastAccessedBlock, uint32(block.number));
        assertEq(mockGasAccounting.bondedTotalSupply(), bondedTotalSupplyBefore + creditedAmount);
        assertEq(bondedAfter, bondedBefore + uint112(creditedAmount));
        assertEq(mockGasAccounting.withdrawals(), withdrawalsBefore + creditedAmount);

        // Testing uint112 boundary values for casting from uint256 to uint112 in _credit()
        uint256 overflowAmount = uint256(type(uint112).max) + 1;
        vm.expectRevert(AtlasErrors.ValueTooLarge.selector);
        mockGasAccounting.credit(solverOp.from, overflowAmount);
    }

    function test_handleSolverAccounting() public {
        solverOp.data = abi.encodePacked("calldata");
        uint256 calldataCost = (solverOp.data.length * mockGasAccounting.calldataLengthPremium()) + 1;
        uint256 gasWaterMark = gasleft() + 5000;
        uint256 maxGasUsed;
        uint112 bondedBefore;
        uint112 bondedAfter;
        uint256 result;

        // FULL_REFUND
        result = EscrowBits._FULL_REFUND;
        maxGasUsed = gasWaterMark + calldataCost;
        maxGasUsed = maxGasUsed * (mockGasAccounting.SURCHARGE_SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE() + mockGasAccounting.BUNDLER_SURCHARGE_RATE()) / mockGasAccounting.SURCHARGE_SCALE()
            * tx.gasprice;
        mockGasAccounting.increaseBondedBalance(solverOp.from, maxGasUsed);
        (bondedBefore,,,,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
        (bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertGt(
            bondedBefore - bondedAfter,
            calldataCost * (mockGasAccounting.SURCHARGE_SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE() + mockGasAccounting.BUNDLER_SURCHARGE_RATE()) / mockGasAccounting.ATLAS_SURCHARGE_RATE()
                * tx.gasprice
        ); // Must be greater than calldataCost
        assertLt(bondedBefore - bondedAfter, maxGasUsed); // Must be less than maxGasUsed

        // NO_REFUND
        result = 1 << uint256(SolverOutcome.InvalidTo);
        (bondedBefore,,,,) = mockGasAccounting.accessData(solverOp.from);
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
        (bondedAfter,,,,) = mockGasAccounting.accessData(solverOp.from);
        assertEq(bondedBefore, bondedAfter);

        // UncoveredResult
        result = 0;
        mockGasAccounting.releaseSolverLock(solverOp, gasWaterMark, result);
    }

    function test_settle() public {
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
    //     settleGasRemainder = settleGasRemainder * mockGasAccounting.SURCHARGE_SCALE() / (mockGasAccounting.SURCHARGE_SCALE() + mockGasAccounting.ATLAS_SURCHARGE_RATE());

    //     // The bundler must be repaid the gas cost between the 2 markers
    //     uint256 diff = rawClaims - settleGasRemainder;
    //     assertEq(diff, claimsPaidToBundler);
    // }
}
