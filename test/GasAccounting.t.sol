// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { GasAccounting } from "../src/contracts/atlas/GasAccounting.sol";
import { AtlasEvents } from "../src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "../src/contracts/types/AtlasErrors.sol";
import { AtlasConstants } from "../src/contracts/types/AtlasConstants.sol";

import { EscrowBits } from "../src/contracts/libraries/EscrowBits.sol";
import { IL2GasCalculator } from "../src/contracts/interfaces/IL2GasCalculator.sol";

import { GasAccLib, GasLedger, BorrowsLedger } from "../src/contracts/libraries/GasAccLib.sol";
import "../src/contracts/libraries/AccountingMath.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/SolverOperation.sol";
import "../src/contracts/types/ConfigTypes.sol";

import { ExecutionEnvironment } from "../src/contracts/common/ExecutionEnvironment.sol";

import { MockL2GasCalculator } from "./base/MockL2GasCalculator.sol";
import { TestAtlas } from "./base/TestAtlas.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

contract GasAccountingTest is AtlasConstants, BaseTest {
    using GasAccLib for GasLedger;
    using GasAccLib for BorrowsLedger;
    using GasAccLib for uint256;
    using AccountingMath for uint256;

    uint256 public constant ONE_GWEI = 1e9;
    uint256 public constant SCALE = AccountingMath._SCALE;
    uint256 public constant A_SURCHARGE = 1_000_000; // 10%
    uint256 public constant B_SURCHARGE = 1_000_000; // 10%

    TestAtlasGasAcc public tAtlas;
    address public executionEnvironment;

    function setUp() public override {
        // Run the base setup
        super.setUp();

        // Compute expected addresses for the deployment
        address expectedAtlasAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment(expectedAtlasAddr);

        // Initialize MockGasAccounting
        tAtlas = new TestAtlasGasAcc(
            DEFAULT_ESCROW_DURATION,
            A_SURCHARGE,
            B_SURCHARGE,
            address(atlasVerification),
            address(simulator),
            deployer,
            address(0),
            address(execEnvTemplate)
        );

        // Create a mock execution environment - the expected caller in many GasAcc functions
        executionEnvironment = makeAddr("ExecutionEnvironment");
    }

    function test_GasAccounting_initializeAccountingValues() public {
        uint256 gasMarker = 123;
        uint256 allSolverOpsGas = 456;
        uint256 msgValue = 789;

        tAtlas.initializeAccountingValues{ value: msgValue }(gasMarker, allSolverOpsGas);

        GasLedger memory gL = tAtlas.getGasLedger();
        BorrowsLedger memory bL = tAtlas.getBorrowsLedger();

        assertEq(gL.remainingMaxGas, gasMarker, "remainingMaxGas not set correctly");
        assertEq(gL.writeoffsGas, 0, "writeoffsGas should be 0");
        assertEq(gL.solverFaultFailureGas, 0, "solverFaultFailureGas should be 0");
        assertEq(gL.unreachedSolverGas, allSolverOpsGas, "unreachedSolverGas not set correctly");
        assertEq(gL.maxApprovedGasSpend, 0, "maxApprovedGasSpend should be 0");
        assertEq(bL.borrows, 0, "borrows should be 0");
        assertEq(bL.repays, msgValue, "repays not set correctly");
    }

    function test_GasAccounting_contribute() public {
        // Testing the external contribute() function:
        uint256 msgValue = 123;

        hoax(userEOA, msgValue);
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, address(0)));
        tAtlas.contribute{ value: msgValue }();

        // Directly testing the internal _contribute() function:
        tAtlas.contribute_internal{ value: msgValue }();

        BorrowsLedger memory bL = tAtlas.getBorrowsLedger();
        assertEq(bL.repays, msgValue, "repays should be msgValue");

        // If msg.value is 0, nothing should change
        tAtlas.contribute_internal{ value: 0 }();

        bL = tAtlas.getBorrowsLedger();
        assertEq(bL.repays, msgValue, "repays should still be msgValue");

        // Calling contribute_internal() again should increase repays again
        tAtlas.contribute_internal{ value: msgValue }();
        bL = tAtlas.getBorrowsLedger();
        assertEq(bL.repays, msgValue * 2, "repays should be 2 * msgValue");
    }

    function test_GasAccounting_borrow() public {
        uint256 atlasStartBalance = 10e18;
        uint256 borrowedAmount = 5e18;
        vm.deal(address(tAtlas), atlasStartBalance);

        // Testing the external borrow() function:

        // Case 1: Borrowing 0 should return without any state changes or value transfers
        vm.prank(executionEnvironment);
        tAtlas.borrow(0);
        assertEq(address(tAtlas).balance, atlasStartBalance, "Atlas balance should not change");

        // Case 2: Only currently active ExecutionEnvironment should be able to borrow
        vm.prank(userEOA);
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InvalidExecutionEnvironment.selector, address(0)));
        tAtlas.borrow(borrowedAmount);

        // Case 3: The active EE can only borrow in an allowed phase (SolverOperation phase or before)
        tAtlas.setLock(executionEnvironment, uint32(0), uint8(ExecutionPhase.AllocateValue));
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        tAtlas.borrow(borrowedAmount);

        // Case 4: Should revert if solver has already called back to Atlas via reconcile()
        tAtlas.setLock(executionEnvironment, uint32(0), uint8(ExecutionPhase.SolverOperation));
        tAtlas.setSolverLock(_SOLVER_CALLED_BACK_MASK);
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        tAtlas.borrow(borrowedAmount);

        // Testing both the external borrow() function and the internal _borrow() function:

        // Case 5: Should revert if Atlas does not have enough ETH
        tAtlas.setSolverLock(0); // removing the `calledBack` flag to unblock
        vm.prank(executionEnvironment);
        vm.expectRevert(
            abi.encodeWithSelector(
                AtlasErrors.InsufficientAtlETHBalance.selector, atlasStartBalance, atlasStartBalance + 1
            )
        );
        tAtlas.borrow(atlasStartBalance + 1);

        // Case 6: Successful borrow sends ETH to the caller and increases borrows in BorrowLedger
        uint256 execEnvBalanceBefore = address(executionEnvironment).balance;
        BorrowsLedger memory bLBefore = tAtlas.getBorrowsLedger();

        vm.prank(executionEnvironment);
        tAtlas.borrow(borrowedAmount);

        BorrowsLedger memory bLAfter = tAtlas.getBorrowsLedger();
        assertEq(
            address(executionEnvironment).balance,
            execEnvBalanceBefore + borrowedAmount,
            "EE balance should increase by borrowedAmount"
        );
        assertEq(
            address(tAtlas).balance,
            atlasStartBalance - borrowedAmount,
            "Atlas balance should decrease by borrowedAmount"
        );
        assertEq(bLAfter.borrows, bLBefore.borrows + borrowedAmount, "Borrows should increase by borrowedAmount");
    }

    function test_GasAccounting_shortfall() public {
        GasLedger memory gL = GasLedger(1_000_000, 0, 0, 0, 0);
        BorrowsLedger memory bL = BorrowsLedger(1e18, 0);
        tAtlas.setGasLedger(gL.pack());
        tAtlas.setBorrowsLedger(bL.pack());

        vm.txGasPrice(1e9); // set gas price to 1 gwei

        // Case 1: Net borrows = 1e18 | gas liability = (1M * 1 gwei * 1 + surcharges)
        (uint256 gasLiability, uint256 borrowLiability) = tAtlas.shortfall();

        assertEq(gasLiability, (1_000_000 * tx.gasprice).withSurcharge(
            A_SURCHARGE + B_SURCHARGE
        ), "gasLiability 1 not as expected");
        assertEq(borrowLiability, 1e18, "borrowLiability 1 should be 1e18");

        // Case 2: Net borrows = -1e18 | gas liability = (200k * 1 gwei * 1 + surcharges)
        tAtlas.setGasLedger(GasLedger(200000, 0, 0, 0, 0).pack());
        tAtlas.setBorrowsLedger(BorrowsLedger(0, 1e18).pack());

        (gasLiability, borrowLiability) = tAtlas.shortfall();

        assertEq(gasLiability, (200_000 * tx.gasprice).withSurcharge(
            A_SURCHARGE + B_SURCHARGE
        ), "gasLiability 2 not as expected");
        assertEq(borrowLiability, 0, "borrowLiability 2 should be 0");
    }

    function test_GasAccounting_reconcile() public {
        // In reality, the solver's contract calls reconcile()
        address solverContract = makeAddr("SolverContract");
        hoax(solverOneEOA, 1e18);
        tAtlas.depositAndBond{ value: 1e18 }(1e18); // solver has 1 ETH bonded
        tAtlas.setSolverLock(uint256(uint160(solverOneEOA)));

        // Solver has a 1M gas liability, and a 1 ETH borrow liability
        GasLedger memory gL = GasLedger(1_000_000, 0, 0, 0, 0);
        BorrowsLedger memory bL = BorrowsLedger(1e18, 0);

        tAtlas.setGasLedger(gL.pack());
        tAtlas.setBorrowsLedger(bL.pack());

        uint256 expectedGasLiability = (1_000_000 * tx.gasprice).withSurcharge(
            A_SURCHARGE + B_SURCHARGE
        );

        (uint256 gasLiability, uint256 borrowLiability) = tAtlas.shortfall();
        assertEq(gasLiability, expectedGasLiability, "gasLiability should be 1M gas * gas price * surcharges");
        assertEq(borrowLiability, 1e18, "borrowLiability should be 1e18");

        // Case 1: should revert if phase is not SolverOperation
        tAtlas.setLock(executionEnvironment, uint32(0), uint8(ExecutionPhase.UserOperation));
        vm.prank(solverContract);
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        tAtlas.reconcile(0);

        // Case 2: should revert if caller is not current solverTo address
        tAtlas.setLock(executionEnvironment, uint32(0), uint8(ExecutionPhase.SolverOperation));
        tAtlas.setSolverTo(solverContract);
        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.InvalidAccess.selector);
        tAtlas.reconcile(0);

        uint256 snapshot = vm.snapshotState();

        // Case 3: if only borrow repaid, and not gas spend approved, solver lock should be:
        // CALLED BACK = true
        // FULFILLED = false
        
        hoax(solverContract, borrowLiability);
        uint256 totalShortfall = tAtlas.reconcile{value: borrowLiability}(0);

        GasLedger memory gLAfter = tAtlas.getGasLedger();
        BorrowsLedger memory bLAfter = tAtlas.getBorrowsLedger();
        uint256 solverLock = tAtlas.getSolverLock();

        assertEq(gLAfter.remainingMaxGas, 1_000_000, "remainingMaxGas should be 1_000_000");
        assertEq(gLAfter.writeoffsGas, 0, "writeoffsGas should be 0");
        assertEq(gLAfter.solverFaultFailureGas, 0, "solverFaultFailureGas should be 0");
        assertEq(gLAfter.unreachedSolverGas, 0, "unreachedSolverGas should be 0");
        assertEq(gLAfter.maxApprovedGasSpend, 0, "maxApprovedGasSpend should be 0");
        assertEq(bLAfter.borrows, 1e18, "borrows should be 1e18");
        assertEq(bLAfter.repays, 1e18, "repays should be 1e18 - repaid borrow debt");
        assertEq(solverLock, (uint256(uint160(solverOneEOA)) | _SOLVER_CALLED_BACK_MASK), "solver lock should be CALLED BACK only");
        assertEq(totalShortfall, gasLiability, "totalShortfall should be gasLiability");

        // Case 4: if only gas spend approved, and borrow not repaid, solver lock should be:
        // CALLED BACK = true
        // FULFILLED = false
        vm.revertToState(snapshot);

        vm.prank(solverContract);
        totalShortfall = tAtlas.reconcile{value: 0}(gasLiability);

        gLAfter = tAtlas.getGasLedger();
        bLAfter = tAtlas.getBorrowsLedger();
        solverLock = tAtlas.getSolverLock();

        assertEq(gLAfter.remainingMaxGas, 1_000_000, "remainingMaxGas should be 1_000_000");
        assertEq(gLAfter.writeoffsGas, 0, "writeoffsGas should be 0");
        assertEq(gLAfter.solverFaultFailureGas, 0, "solverFaultFailureGas should be 0");
        assertEq(gLAfter.unreachedSolverGas, 0, "unreachedSolverGas should be 0");
        assertEq(gLAfter.maxApprovedGasSpend, gasLiability / tx.gasprice, "maxApprovedGasSpend should be gasLiability / tx.gasprice");
        assertEq(bLAfter.borrows, 1e18, "borrows should be 1e18");
        assertEq(bLAfter.repays, 0, "repays should be 0");
        assertEq(solverLock, (uint256(uint160(solverOneEOA)) | _SOLVER_CALLED_BACK_MASK), "solver lock should be CALLED BACK only");
        assertEq(totalShortfall, borrowLiability + gasLiability, "totalShortfall should be borrowLiability + gasLiability");

        // Case 5: if no gas spend approved, but repayment excess is enough, solver lock should be:
        // CALLED BACK = true
        // FULFILLED = true
        vm.revertToState(snapshot);

        hoax(solverContract, borrowLiability + gasLiability);
        totalShortfall = tAtlas.reconcile{value: borrowLiability + gasLiability}(0);

        gLAfter = tAtlas.getGasLedger();
        bLAfter = tAtlas.getBorrowsLedger();
        solverLock = tAtlas.getSolverLock();

        assertEq(gLAfter.remainingMaxGas, 1_000_000, "remainingMaxGas should be 1_000_000");
        assertEq(gLAfter.writeoffsGas, 0, "writeoffsGas should be 0");
        assertEq(gLAfter.solverFaultFailureGas, 0, "solverFaultFailureGas should be 0");
        assertEq(gLAfter.unreachedSolverGas, 0, "unreachedSolverGas should be 0");
        assertEq(gLAfter.maxApprovedGasSpend, 0, "maxApprovedGasSpend should be 0");
        assertEq(bLAfter.borrows, 1e18, "borrows should be 1e18");
        assertEq(bLAfter.repays, borrowLiability + gasLiability, "repays should be borrowLiability + gasLiability");
        assertEq(solverLock, (uint256(uint160(solverOneEOA)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK), "solver lock should be CALLED BACK and FULFILLED");
        assertEq(totalShortfall, 0, "totalShortfall should be 0");

        // Case 6: if gas spend approved and borrow repaid exactly, solver lock should be:
        // CALLED BACK = true
        // FULFILLED = true
        vm.revertToState(snapshot);

        hoax(solverContract, borrowLiability);
        totalShortfall = tAtlas.reconcile{value: borrowLiability}(gasLiability);

        gLAfter = tAtlas.getGasLedger();
        bLAfter = tAtlas.getBorrowsLedger();
        solverLock = tAtlas.getSolverLock();

        assertEq(gLAfter.remainingMaxGas, 1_000_000, "remainingMaxGas should be 1_000_000");
        assertEq(gLAfter.writeoffsGas, 0, "writeoffsGas should be 0");
        assertEq(gLAfter.solverFaultFailureGas, 0, "solverFaultFailureGas should be 0");
        assertEq(gLAfter.unreachedSolverGas, 0, "unreachedSolverGas should be 0");
        assertEq(gLAfter.maxApprovedGasSpend, (gasLiability/tx.gasprice), "maxApprovedGasSpend should be gasLiability/tx.gasprice");
        assertEq(bLAfter.borrows, 1e18, "borrows should be 1e18");
        assertEq(bLAfter.repays, 1e18, "repays should be 1e18 - repaid borrow debt");
        assertEq(solverLock, (uint256(uint160(solverOneEOA)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK), "solver lock should be CALLED BACK and FULFILLED");
        assertEq(totalShortfall, 0, "totalShortfall should be 0");
    }

    function test_show_borrows_and_repays_accumulate_after_multiple_reconciles() public {
        // Setup two solvers
        address solver1Contract = makeAddr("Solver1Contract");
        address solver2Contract = makeAddr("Solver2Contract");
        
        // Setup solver1
        hoax(solverOneEOA, 1e18);
        tAtlas.depositAndBond{ value: 1e18 }(1e18);
        
        // Setup solver2
        hoax(solverTwoEOA, 1e18);
        tAtlas.depositAndBond{ value: 1e18 }(1e18);

        // Set initial solver lock for solver1
        tAtlas.setLock(executionEnvironment, uint32(0), uint8(ExecutionPhase.SolverOperation));
        tAtlas.setSolverTo(solver1Contract);
        // Set solver lock with just the address, no flags yet
        tAtlas.setSolverLock(uint256(uint160(solverOneEOA)));

        // Setup gas ledger for both solvers
        GasLedger memory gL = GasLedger(2_000_000, 0, 0, 2_000_000, 0);
        tAtlas.setGasLedger(gL.pack());

        // Fund Atlas contract so it can handle borrows
        vm.deal(address(tAtlas), 10e18);

        // Solver1 borrows 1 ETH
        hoax(executionEnvironment);
        tAtlas.borrow(1e18);

        // Verify borrows ledger after solver1's borrow
        BorrowsLedger memory bL = tAtlas.getBorrowsLedger();
        assertEq(bL.borrows, 1e18, "borrows should be 1e18 after solver1's borrow");
        assertEq(bL.repays, 0, "repays should be 0 before solver1's reconcile");

        uint256 expectedGasLiability = (1_000_000 * tx.gasprice).withSurcharge(
            A_SURCHARGE + B_SURCHARGE
        );

        // Solver1 reconciles successfully
        hoax(solver1Contract, 1e18);
        uint256 totalShortfall = tAtlas.reconcile{value: 1e18}(expectedGasLiability);

        // Verify solver1's state
        uint256 solver1Lock = tAtlas.getSolverLock();
        // The lock should be: solver address in lower 160 bits | CALLED_BACK_MASK | FULFILLED_MASK
        assertEq(solver1Lock, (uint256(uint160(solverOneEOA)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK), 
            "solver1 lock should be CALLED BACK and FULFILLED");
        assertEq(totalShortfall, 0, "solver1 shortfall should be 0");

        // Verify borrows ledger after solver1's reconcile
        bL = tAtlas.getBorrowsLedger();
        assertEq(bL.borrows, 1e18, "borrows should still be 1e18 after solver1's reconcile");
        assertEq(bL.repays, 1e18, "repays should be 1e18 after solver1's reconcile");

        // Test solver2 reconciliation
        tAtlas.setSolverTo(solver2Contract);
        // Set solver lock with just the address, no flags yet
        tAtlas.setSolverLock(uint256(uint160(solverTwoEOA)));

        // Solver2 borrows 1 ETH
        hoax(executionEnvironment);
        tAtlas.borrow(1e18);

        // Verify borrows ledger after solver2's borrow
        bL = tAtlas.getBorrowsLedger();
        assertEq(bL.borrows, 2e18, "borrows should be 2e18 after solver2's borrow");
        assertEq(bL.repays, 1e18, "repays should still be 1e18 before solver2's reconcile");

        // Solver2 reconciles successfully
        hoax(solver2Contract, 1e18);
        totalShortfall = tAtlas.reconcile{value: 1e18}(expectedGasLiability);

        // Verify solver2's state
        uint256 solver2Lock = tAtlas.getSolverLock();
        // The lock should be: solver address in lower 160 bits | CALLED_BACK_MASK | FULFILLED_MASK
        assertEq(solver2Lock, (uint256(uint160(solverTwoEOA)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK), 
            "solver2 lock should be CALLED BACK and FULFILLED");
        assertEq(totalShortfall, 0, "solver2 shortfall should be 0");

        // Verify final state
        GasLedger memory finalGL = tAtlas.getGasLedger();
        BorrowsLedger memory finalBL = tAtlas.getBorrowsLedger();
        
        assertEq(finalBL.borrows, 2e18, "total borrows should be 2e18");
        assertEq(finalBL.repays, 2e18, "total repays should be 2e18");
        assertEq(finalGL.maxApprovedGasSpend, (expectedGasLiability/tx.gasprice), 
            "maxApprovedGasSpend is not being summed, this is OK because handleFailSolverAccounting doesn't use maxApprovedGasSpend");
    }

    function test_GasAccounting_assign() public {
        vm.deal(solverOneEOA, 6e18); // 3 to unbonded, 2 unbonding, 1 bonded
        vm.startPrank(solverOneEOA);
        tAtlas.depositAndBond{ value: 6e18 }(3e18);
        tAtlas.unbond(2e18);

        EscrowAccountAccessData memory accountData = tAtlas.getAccessData(solverOneEOA);
        uint256 unbonded = tAtlas.balanceOf(solverOneEOA);
        uint256 unbonding = tAtlas.balanceOfUnbonding(solverOneEOA);
        uint256 bonded = tAtlas.balanceOfBonded(solverOneEOA);
        uint256 bondedTotalSupply = tAtlas.bondedTotalSupply(); // bonded + unbonding included in bondedTotalSupply
        uint32 lastAccessedBlock;

        vm.roll(block.number + 100); // Move 100 blocks forward

        // Take state snapshot to revert to for each check below
        uint256 snapshot = vm.snapshotState();

        // Case 1: Reverts if amount is over uint112
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector, 112, uint256(type(uint112).max) + 1
            )
        );
        tAtlas.assign(accountData, solverOneEOA, uint256(type(uint112).max) + 1);

        // Case 2: If bonded balance is sufficient, does not disrupt unbonding or unbonded balances
        tAtlas.assign(accountData, solverOneEOA, 1e18);

        (, lastAccessedBlock,,,) = tAtlas.accessData(solverOneEOA);
        assertEq(tAtlas.balanceOf(solverOneEOA), unbonded, "unbonded balance should not change");
        assertEq(tAtlas.balanceOfUnbonding(solverOneEOA), unbonding, "unbonding balance should not change");
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), bonded - 1e18, "bonded balance should decrease by 1e18");
        assertEq(tAtlas.bondedTotalSupply(), bondedTotalSupply - 1e18, "bondedTotalSupply should decrease by 1e18");
        assertEq(lastAccessedBlock, accountData.lastAccessedBlock + 100, "lastAccessedBlock should be updated");

        // Case 3: If bonded balance is insufficient, takes from unbonding balance
        vm.revertToState(snapshot);
        tAtlas.assign(accountData, solverOneEOA, 2e18); // should take 1 from bonded, 1 from unbonding

        assertEq(tAtlas.balanceOf(solverOneEOA), unbonded, "unbonded balance should not change");
        assertEq(tAtlas.balanceOfUnbonding(solverOneEOA), unbonding - 1e18, "unbonding balance should decrease by 1e18");
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), bonded - 1e18, "bonded balance should decrease by 1e18");
        assertEq(tAtlas.bondedTotalSupply(), bondedTotalSupply - 2e18, "bondedTotalSupply should decrease by 2e18");
        assertEq(lastAccessedBlock, accountData.lastAccessedBlock + 100, "lastAccessedBlock should be updated");

        // Case 4: If bonded + unbonding balance is insufficient, takes all bonded + unbonding and returns deficit
        vm.revertToState(snapshot);
        uint256 expectedDeficit = 4e18 - (bonded + unbonding); // 4 - (1 + 2) = 1: Should be a deficit of 1e18
        uint256 deficit = tAtlas.assign(accountData, solverOneEOA, 4e18);

        assertEq(tAtlas.balanceOf(solverOneEOA), unbonded, "unbonded balance should not change");
        assertEq(tAtlas.balanceOfUnbonding(solverOneEOA), 0, "unbonding balance should be 0");
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 0, "bonded balance should be 0");
        assertEq(tAtlas.bondedTotalSupply(), bondedTotalSupply - 3e18, "bondedTotalSupply should decrease by 3e18");
        assertEq(lastAccessedBlock, accountData.lastAccessedBlock + 100, "lastAccessedBlock should be updated");
        assertEq(deficit, expectedDeficit, "deficit should be 1e18");
    }

    function test_GasAccounting_credit() public {
        // Case 1: Should revert if amount is over uint112
        EscrowAccountAccessData memory accountData = tAtlas.getAccessData(solverOneEOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector, 112, uint256(type(uint112).max) + 1
            )
        );
        tAtlas.credit(accountData, uint256(type(uint112).max) + 1);

        // Case 2: Should credit the account with the amount, and bondedTotalSupply should increase
        EscrowAccountAccessData memory newAccData = tAtlas.credit(accountData, 1e18);

        assertEq(newAccData.bonded, accountData.bonded + 1e18, "accountData.bonded should increase by 1e18");
        assertEq(tAtlas.bondedTotalSupply(), 1e18, "bondedTotalSupply should be 1e18");
    }

    function test_GasAccounting_handleSolverFailAccounting() public {
        // 3 test scenarios:
        // 1. result = bundler fault
        // 2. result = solver fault, no deficit
        // 3. result = solver fault, with deficit

        SolverOperation memory solverOp;
        solverOp.from = solverOneEOA;
        solverOp.data = new bytes(300); // For easy calldata gas estimation

        vm.deal(solverOneEOA, 2e18); // 1 to unbonded, 1 bonded
        vm.startPrank(solverOneEOA);
        tAtlas.depositAndBond{ value: 2e18 }(1e18);

        uint256 dConfigSolverGasLimit = 1_000_000;
        vm.txGasPrice(1e9); // set gas price to 1 gwei
        GasLedger memory gLBefore = GasLedger(2_000_000, 0, 0, 0, 0);
        tAtlas.setGasLedger(gLBefore.pack()); // remainingMaxGas starts at 2M gas so it can decrease

        gLBefore = tAtlas.getGasLedger();
        EscrowAccountAccessData memory accountDataBefore = tAtlas.getAccessData(solverOneEOA);

        uint256 snapshot = vm.snapshotState();

        // ===============================
        // Case 1: result = bundler fault
        // ===============================
        uint256 result = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(EscrowBits.bundlersFault(result), true, "result should be a bundler fault");

        uint256 gasWaterMark = 1_000_000;
        uint256 gasLeft = 200_000;
        uint256 estGasUsed = (gasWaterMark + _SOLVER_BASE_GAS_USED - gasLeft)
            + GasAccLib.solverOpCalldataGas(solverOp.data.length, address(0));

        tAtlas.handleSolverFailAccounting{ gas: gasLeft }(solverOp, dConfigSolverGasLimit, gasWaterMark, result, false);

        GasLedger memory gLAfter = tAtlas.getGasLedger();
        EscrowAccountAccessData memory accountDataAfter = tAtlas.getAccessData(solverOneEOA);

        assertApproxEqRel(
            gLAfter.writeoffsGas,
            gLBefore.writeoffsGas + estGasUsed,
            0.02e18, // 2% tolerance
            "writeoffsGas should increase by estGasUsed"
        );
        assertEq(
            gLAfter.solverFaultFailureGas, gLBefore.solverFaultFailureGas, "solverFaultFailureGas should not change"
        );
        assertEq(accountDataAfter.bonded, accountDataBefore.bonded, "bonded balance should not change");
        assertEq(accountDataAfter.auctionWins, accountDataBefore.auctionWins, "auctionWins should not change");
        assertEq(accountDataAfter.auctionFails, accountDataBefore.auctionFails, "auctionFails should not change");
        assertEq(
            accountDataAfter.totalGasValueUsed,
            accountDataBefore.totalGasValueUsed,
            "totalGasValueUsed should not change"
        );

        // ===============================
        // Case 2: result = solver fault, no assign deficit
        // ===============================
        vm.revertToState(snapshot);
        result = 1 << uint256(SolverOutcome.SolverOpReverted);
        assertEq(EscrowBits.bundlersFault(result), false, "result should not be a bundler fault");

        // No change in gasWaterMark, gasLeft, or estGasUsed --> no assign deficit
        uint256 estGasValueCharged =
            estGasUsed.withSurcharge(A_SURCHARGE + B_SURCHARGE) * tx.gasprice;

        tAtlas.handleSolverFailAccounting{ gas: gasLeft }(solverOp, dConfigSolverGasLimit, gasWaterMark, result, false);

        gLAfter = tAtlas.getGasLedger();
        accountDataAfter = tAtlas.getAccessData(solverOneEOA);

        assertApproxEqRel(
            gLAfter.solverFaultFailureGas,
            gLBefore.solverFaultFailureGas + estGasUsed,
            0.02e18, // 2% tolerance
            "solverFaultFailureGas should increase by estGasUsed"
        );
        assertEq(gLAfter.writeoffsGas, gLBefore.writeoffsGas, "writeoffsGas should not change");
        assertApproxEqRel(
            accountDataAfter.bonded,
            accountDataBefore.bonded - estGasValueCharged,
            0.02e18, // 2% tolerance
            "bonded balance should not change"
        );
        assertEq(accountDataAfter.auctionWins, accountDataBefore.auctionWins, "auctionWins should not change");
        assertEq(accountDataAfter.auctionFails, accountDataBefore.auctionFails + 1, "auctionFails should increase by 1");
        assertApproxEqRel(
            accountDataAfter.totalGasValueUsed,
            accountDataBefore.totalGasValueUsed + (estGasValueCharged / _GAS_VALUE_DECIMALS_TO_DROP),
            0.02e18, // 2% tolerance
            "totalGasValueUsed should increase by estGasValueCharged"
        );

        // ===============================
        // Case 3: result = solver fault, with assign deficit
        // ===============================
        vm.revertToState(snapshot);
        result = 1 << uint256(SolverOutcome.SolverOpReverted);
        assertEq(EscrowBits.bundlersFault(result), false, "result should not be a bundler fault");

        // estGasUsed * tx.gasprice should be > solver's 1e18 bonded, to cause a deficit
        gasWaterMark = 2e9; // After solver pays 1e18, leaves approx 1e18 deficit
        gasLeft = 100_000;
        estGasUsed = (gasWaterMark + _SOLVER_BASE_GAS_USED - gasLeft)
            + GasAccLib.solverOpCalldataGas(solverOp.data.length, address(0));
        uint256 estAssignValueInclSurcharges =
            estGasUsed.withSurcharge(A_SURCHARGE + B_SURCHARGE) * tx.gasprice;
        uint256 estDeficit = estAssignValueInclSurcharges - 1e18; // 1e18 bonded balance
        uint256 estGasWrittenOff = estGasUsed * estDeficit / estAssignValueInclSurcharges;

        tAtlas.handleSolverFailAccounting{ gas: gasLeft }(solverOp, dConfigSolverGasLimit, gasWaterMark, result, false);

        gLAfter = tAtlas.getGasLedger();
        accountDataAfter = tAtlas.getAccessData(solverOneEOA);

        assertApproxEqRel(
            gLAfter.solverFaultFailureGas,
            gLBefore.solverFaultFailureGas + (estGasUsed - estGasWrittenOff),
            0.02e18, // 2% tolerance
            "solverFaultFailureGas should increase by estGasUsed excl. deficit"
        );
        assertApproxEqRel(
            gLAfter.writeoffsGas,
            gLBefore.writeoffsGas + estGasWrittenOff,
            0.02e18, // 2% tolerance
            "writeoffsGas should increase by deficit"
        );
        assertEq(accountDataAfter.bonded, 0, "bonded balance should be 0 if deficit caused");
        assertEq(accountDataAfter.auctionWins, accountDataBefore.auctionWins, "auctionWins should not change");
        assertEq(accountDataAfter.auctionFails, accountDataBefore.auctionFails + 1, "auctionFails should increase by 1");
        assertApproxEqRel(
            accountDataAfter.totalGasValueUsed,
            accountDataBefore.totalGasValueUsed + (1e18 / _GAS_VALUE_DECIMALS_TO_DROP),
            0.02e18, // 2% tolerance
            "totalGasValueUsed should increase by deficit"
        );

        // ===============================
        // Case 4: result = bundler fault, exPostBids = true
        // ===============================
        vm.revertToState(snapshot);
        result = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(EscrowBits.bundlersFault(result), true, "result should be a bundler fault");

        gasWaterMark = 1_000_000;
        gasLeft = 200_000;
        estGasUsed = (gasWaterMark + _SOLVER_BASE_GAS_USED - gasLeft); // Calldata excluded

        tAtlas.handleSolverFailAccounting{ gas: gasLeft }(solverOp, dConfigSolverGasLimit, gasWaterMark, result, true);

        gLAfter = tAtlas.getGasLedger();
        accountDataAfter = tAtlas.getAccessData(solverOneEOA);

        assertApproxEqRel(
            gLAfter.writeoffsGas,
            gLBefore.writeoffsGas + estGasUsed,
            0.01e18, // 1% tolerance
            "writeoffsGas should increase by estGasUsed"
        );
        assertEq(
            gLAfter.solverFaultFailureGas, gLBefore.solverFaultFailureGas, "solverFaultFailureGas should not change"
        );
        assertEq(accountDataAfter.bonded, accountDataBefore.bonded, "bonded balance should not change");
        assertEq(accountDataAfter.auctionWins, accountDataBefore.auctionWins, "auctionWins should not change");
        assertEq(accountDataAfter.auctionFails, accountDataBefore.auctionFails, "auctionFails should not change");
        assertEq(
            accountDataAfter.totalGasValueUsed,
            accountDataBefore.totalGasValueUsed,
            "totalGasValueUsed should not change"
        );
    }

    function test_GasAccounting_writeOffBidFindGas() public {
        uint256 gasUsed = 1_000_000;
        tAtlas.writeOffBidFindGas(gasUsed);

        GasLedger memory gL = tAtlas.getGasLedger();
        assertEq(gL.writeoffsGas, gasUsed, "writeoffsGas should be gasUsed");
    }

    function test_GasAccounting_chargeUnreachedSolversForCalldata() public {
        SolverOperation[] memory solverOps = new SolverOperation[](3);
        solverOps[0].from = solverOneEOA;
        solverOps[0].data = new bytes(300);
        solverOps[1].from = solverTwoEOA;
        solverOps[1].data = new bytes(300);
        solverOps[2].from = solverThreeEOA;
        solverOps[2].data = new bytes(300);

        vm.txGasPrice(1e9); // set gas price to 1 gwei

        GasLedger memory gL = GasLedger(0, 0, 0, 0, 0);
        uint256 solverOpCalldataGasValue =
            GasAccLib.solverOpCalldataGas(solverOps[0].data.length, address(0)) * tx.gasprice;
        uint256 loopIterGas = 4000; // approx gas used for 1 loop
        uint256 constGas = 350; // approx constant gas used besides the loop

        // Give solvers bonded atlETH to pay with
        hoax(solverOneEOA, 1e18);
        tAtlas.depositAndBond{ value: 1e18 }(1e18);
        hoax(solverTwoEOA, 1e18);
        tAtlas.depositAndBond{ value: 1e18 }(1e18);
        hoax(solverThreeEOA, 1e18);
        tAtlas.depositAndBond{ value: 1e18 }(1e18);

        // Sum of starting bonded balances should be 3e18
        assertEq(tAtlas.bondedTotalSupply(), 3e18, "bondedTotalSupply should be 3e18");
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 1e18, "solverOneEOA bonded balance should start 1e18");
        assertEq(tAtlas.balanceOfBonded(solverTwoEOA), 1e18, "solverTwoEOA bonded balance should start 1e18");
        assertEq(tAtlas.balanceOfBonded(solverThreeEOA), 1e18, "solverThreeEOA bonded balance should start 1e18");

        uint256 snapshot = vm.snapshotState();

        // ===============================
        // Case 1: No unreached solvers -> winning solver idx = 2
        // ===============================
        uint256 unreachedCalldataValuePaid = tAtlas.chargeUnreachedSolversForCalldata(solverOps, gL, 2);

        GasLedger memory gLAfter = tAtlas.getGasLedger();

        assertEq(unreachedCalldataValuePaid, 0, "unreachedCalldataValuePaid should be 0");
        assertEq(tAtlas.bondedTotalSupply(), 3e18, "bondedTotalSupply should be 3e18");
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 1e18, "solverOneEOA bonded balance should be 1e18");
        assertEq(tAtlas.balanceOfBonded(solverTwoEOA), 1e18, "solverTwoEOA bonded balance should be 1e18");
        assertEq(tAtlas.balanceOfBonded(solverThreeEOA), 1e18, "solverThreeEOA bonded balance should be 1e18");
        assertApproxEqRel(
            gLAfter.writeoffsGas,
            constGas, // no loops, just constant gas
            0.1e18, // 10% tolerance, because smol number
            "writeoffsGas should not change"
        );

        // ===============================
        // Case 2: 1 unreached solver -> winning solver idx = 1
        // ===============================
        vm.revertToState(snapshot);

        unreachedCalldataValuePaid = tAtlas.chargeUnreachedSolversForCalldata(solverOps, gL, 1);

        gLAfter = tAtlas.getGasLedger();

        assertEq(
            unreachedCalldataValuePaid,
            solverOpCalldataGasValue,
            "unreachedCalldataValuePaid should be 1x solverOpCalldataGasValue"
        );
        assertEq(
            tAtlas.bondedTotalSupply(),
            3e18 - solverOpCalldataGasValue,
            "bondedTotalSupply should be 3e18 - solverOpCalldataGasValue"
        );
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 1e18, "solverOneEOA bonded balance should be 1e18");
        assertEq(tAtlas.balanceOfBonded(solverTwoEOA), 1e18, "solverTwoEOA bonded balance should be 1e18");
        assertEq(
            tAtlas.balanceOfBonded(solverThreeEOA),
            1e18 - solverOpCalldataGasValue,
            "solverThreeEOA bonded balance should be 1e18 - solverOpCalldataGasValue"
        );
        assertApproxEqRel(
            gLAfter.writeoffsGas,
            loopIterGas + constGas, // 1 iteration + constant gas
            0.02e18, // 2% tolerance
            "writeoffsGas should increase by approx 1 loop"
        );

        // ===============================
        // Case 3: 2 unreached solvers -> winning solver idx = 0
        // ===============================
        vm.revertToState(snapshot);

        unreachedCalldataValuePaid = tAtlas.chargeUnreachedSolversForCalldata(solverOps, gL, 0);

        gLAfter = tAtlas.getGasLedger();

        assertEq(
            unreachedCalldataValuePaid,
            solverOpCalldataGasValue * 2,
            "unreachedCalldataValuePaid should be 2x solverOpCalldataGasValue"
        );
        assertEq(
            tAtlas.bondedTotalSupply(),
            3e18 - (2 * solverOpCalldataGasValue),
            "bondedTotalSupply should be 3e18 - 2 * solverOpCalldataGasValue"
        );
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 1e18, "solverOneEOA bonded balance should be 1e18");
        assertEq(
            tAtlas.balanceOfBonded(solverTwoEOA),
            1e18 - solverOpCalldataGasValue,
            "solverTwoEOA bonded balance should be 1e18 - solverOpCalldataGasValue"
        );
        assertEq(
            tAtlas.balanceOfBonded(solverThreeEOA),
            1e18 - solverOpCalldataGasValue,
            "solverThreeEOA bonded balance should be 1e18 - solverOpCalldataGasValue"
        );
        assertApproxEqRel(
            gLAfter.writeoffsGas,
            2 * loopIterGas + constGas, // 2 iterations + constant gas
            0.02e18, // 2% tolerance
            "writeoffsGas should increase by approx 2 loops"
        );
    }

    function test_GasAccounting_settle() public {
        Context memory ctx;
        GasLedger memory gL;
        uint256 gasMarker = 5_100_000; // About 5M gas used
        uint256 settleGas = 100_000;
        address gasRefundBeneficiary = address(0);
        uint256 unreachedCalldataValuePaid = 100_000 * 1e9; // 100k gas * 1 gwei gas price

        // Random numbers to make sure the winning solver gas calc is working
        uint48 writeoffsGas = 700_000;
        uint48 solverFaultFailureGas = 250_000;

        vm.txGasPrice(1e9); // set gas price to 1 gwei

        // solverOne is last solver (i.e. the winner if ctx.solverSuccessful = true)
        tAtlas.setSolverLock(uint256(uint160(solverOneEOA)));

        ctx.solverSuccessful = true;
        ctx.bundler = userEOA;

        // ============================================
        // Case 1: reverts if repays < borrows
        // ============================================

        BorrowsLedger memory bL = BorrowsLedger(1e18, 0);
        tAtlas.setBorrowsLedger(bL.pack());
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.BorrowsNotRepaid.selector, 1e18, 0));
        tAtlas.settle{gas: settleGas}(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid, false);

        // Reset borrows ledger back to neutral
        tAtlas.setBorrowsLedger(BorrowsLedger(0,0).pack());

        // ============================================
        // Case 2: solverOne wins and has no bonded atlETH | deficit too large --> revert expected
        // ============================================

        vm.expectRevert(); // Difficult to predict error values - but should be AssignDeficitTooLarge() error
        tAtlas.settle{gas: settleGas}(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid, false);

        // ============================================
        // Case 3: solverOne wins and has bonded atlETH
        // ============================================

        vm.deal(address(tAtlas), 1e18); // Give Atlas ETH as if paid from failed/unreached solvers
        hoax(solverOneEOA, 1e18); // Give winning solver 1 bonded atlETH
        tAtlas.depositAndBond{ value: 1e18 }(1e18);
        EscrowAccountAccessData memory aDataBefore = tAtlas.getAccessData(solverOneEOA);
        uint256 bundlerBalanceBefore = userEOA.balance;
        uint256 atlasSurchargeBefore = tAtlas.cumulativeSurcharge();
        gL = GasLedger(0, writeoffsGas, solverFaultFailureGas, 0, 0);

        uint256 snapshot = vm.snapshotState();

        // calculate expected winning solver charge
        uint256 estWinningSolverCharge = (gasMarker - writeoffsGas - solverFaultFailureGas - (unreachedCalldataValuePaid / tx.gasprice) - settleGas).withSurcharge(A_SURCHARGE + B_SURCHARGE) * tx.gasprice;

        // calculate expected bundler refund 
        uint256 estBundlerRefund = estWinningSolverCharge
            * (SCALE + B_SURCHARGE)
            / (SCALE + A_SURCHARGE + B_SURCHARGE);
        estBundlerRefund += unreachedCalldataValuePaid;
        estBundlerRefund += (uint256(solverFaultFailureGas).withSurcharge(B_SURCHARGE) * tx.gasprice);

        // calculate expected atlas surcharge
        uint256 estAtlasSurcharge = estWinningSolverCharge * (A_SURCHARGE)
            / (SCALE + A_SURCHARGE + B_SURCHARGE);
        estAtlasSurcharge += (uint256(solverFaultFailureGas).getSurcharge(A_SURCHARGE) * tx.gasprice);

        // DO SETTLE CALL
        (uint256 claimsPaidToBundler, uint256 netAtlasGasSurcharge) = tAtlas.settle{gas: settleGas}(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid, false);

        EscrowAccountAccessData memory aDataAfter = tAtlas.getAccessData(solverOneEOA);

        assertApproxEqRel(
            tAtlas.balanceOfBonded(solverOneEOA),
            1e18 - estWinningSolverCharge,
            0.01e18, // 1% tolerance
            "winning solver bonded balance should decrease by estWinningSolverCharge"
        );
        assertApproxEqRel(
            claimsPaidToBundler,
            estBundlerRefund,
            0.01e18, // 1% tolerance
            "C3: claimsPaidToBundler should be estBundlerRefund"
        );
        assertEq(bundlerBalanceBefore + claimsPaidToBundler, userEOA.balance, "bundler balance should increase by estWinningSolverCharge");
        assertApproxEqRel(
            netAtlasGasSurcharge,
            estAtlasSurcharge,
            0.01e18, // 1% tolerance
            "netAtlasGasSurcharge should be estAtlasSurcharge"
        );
        assertEq(tAtlas.cumulativeSurcharge(), atlasSurchargeBefore + netAtlasGasSurcharge, "cumulativeSurcharge should increase by netAtlasGasSurcharge");
        assertEq(aDataAfter.auctionWins, aDataBefore.auctionWins + 1, "auctionWins should increase by 1");
        assertEq(aDataAfter.auctionFails, aDataBefore.auctionFails, "auctionFails should not change");
        assertApproxEqRel(
            aDataAfter.totalGasValueUsed,
            aDataBefore.totalGasValueUsed + (estWinningSolverCharge / _GAS_VALUE_DECIMALS_TO_DROP),
            0.01e18, // 1% tolerance
            "totalGasValueUsed should increase by estWinningSolverCharge"
        );
        assertEq(tAtlas.getPhase(), uint8(ExecutionPhase.FullyLocked), "phase should be FullyLocked");

        // ============================================
        // Case 4: no winning solver
        // ============================================
        vm.revertToState(snapshot);

        ctx.solverSuccessful = false;
        solverFaultFailureGas = 10_000_000; // large solver failure gas, to trigger 80% bundler cap
        gL = GasLedger(0, writeoffsGas, solverFaultFailureGas, 0, 0);

        uint256 bundlerRefundBeforeCap = unreachedCalldataValuePaid 
            + uint256(solverFaultFailureGas).withSurcharge(B_SURCHARGE) * tx.gasprice;

        // calculate expected bundler refund --> hits the 80% cap
        estBundlerRefund = (gasMarker - writeoffsGas - settleGas) * 8 / 10 * tx.gasprice;

        // calculate expected atlas surcharge --> gets any bundler surcharge over 80% cap
        estAtlasSurcharge = uint256(solverFaultFailureGas).getSurcharge(A_SURCHARGE) * tx.gasprice;
        estAtlasSurcharge += bundlerRefundBeforeCap - estBundlerRefund;

        // DO SETTLE CALL
        (claimsPaidToBundler, netAtlasGasSurcharge) = tAtlas.settle{gas: settleGas}(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid, false);

        aDataAfter = tAtlas.getAccessData(solverOneEOA);

        // solverOne is not winner - no charge or change in analytics expected
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 1e18, "solverOne is not winner - no balance change");
        assertEq(aDataAfter.auctionWins, aDataBefore.auctionWins, "auctionWins should not change");
        assertEq(aDataAfter.auctionFails, aDataBefore.auctionFails, "auctionFails should not change");
        assertEq(aDataAfter.totalGasValueUsed, aDataBefore.totalGasValueUsed, "totalGasValueUsed should not change");

        // check bundler refund was capped at 80%
        assertApproxEqRel(
            claimsPaidToBundler,
            estBundlerRefund,
            0.01e18, // 1% tolerance
            "C4: claimsPaidToBundler should be estBundlerRefund"
        );
        assertEq(bundlerBalanceBefore + claimsPaidToBundler, userEOA.balance, "bundler balance should increase by estBundlerRefund");
        assertTrue(estBundlerRefund < bundlerRefundBeforeCap, "bundler refund should be capped at 80%");

        // check atlas surcharge included excess bundler surcharge above 80% cap
        assertApproxEqRel(
            netAtlasGasSurcharge,
            estAtlasSurcharge,
            0.01e18, // 1% tolerance
            "netAtlasGasSurcharge should be estAtlasSurcharge"
        );
        assertEq(tAtlas.cumulativeSurcharge(), atlasSurchargeBefore + netAtlasGasSurcharge, "cumulativeSurcharge should increase by netAtlasGasSurcharge");

        assertEq(tAtlas.getPhase(), uint8(ExecutionPhase.FullyLocked), "phase should be FullyLocked");

        // ============================================
        // Case 5: no winning solver, multipleSuccessfulSolvers is true
        // ============================================
        vm.revertToState(snapshot);

        ctx.solverSuccessful = false;
        solverFaultFailureGas = 10_000_000; // large solver failure gas, to trigger 80% bundler cap
        gL = GasLedger(0, writeoffsGas, solverFaultFailureGas, 0, 0);

        bundlerRefundBeforeCap = unreachedCalldataValuePaid 
            + uint256(solverFaultFailureGas).withSurcharge(B_SURCHARGE) * tx.gasprice;

        // calculate expected atlas surcharge
        estAtlasSurcharge = uint256(solverFaultFailureGas).getSurcharge(A_SURCHARGE) * tx.gasprice;

        // DO SETTLE CALL
        (claimsPaidToBundler, netAtlasGasSurcharge) = tAtlas.settle{gas: settleGas}(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid, true);

        aDataAfter = tAtlas.getAccessData(solverOneEOA);

        // solverOne is not winner - no charge or change in analytics expected
        assertEq(tAtlas.balanceOfBonded(solverOneEOA), 1e18, "solverOne is not winner - no balance change");
        assertEq(aDataAfter.auctionWins, aDataBefore.auctionWins, "auctionWins should not change");
        assertEq(aDataAfter.auctionFails, aDataBefore.auctionFails, "auctionFails should not change");
        assertEq(aDataAfter.totalGasValueUsed, aDataBefore.totalGasValueUsed, "totalGasValueUsed should not change");

        // check bundler refund was not capped at 80%
        assertApproxEqRel(
            claimsPaidToBundler,
            bundlerRefundBeforeCap,
            0.01e18, // 1% tolerance
            "C5: claimsPaidToBundler should be BundlerRefundBeforeCap"
        );
        assertEq(bundlerBalanceBefore + claimsPaidToBundler, userEOA.balance, "bundler balance should increase by BundlerRefundBeforeCap");

        // check atlas surcharge
        assertApproxEqRel(
            netAtlasGasSurcharge,
            estAtlasSurcharge,
            0.01e18, // 1% tolerance
            "netAtlasGasSurcharge should be estAtlasSurcharge"
        );
        assertEq(tAtlas.cumulativeSurcharge(), atlasSurchargeBefore + netAtlasGasSurcharge, "cumulativeSurcharge should increase by netAtlasGasSurcharge");

        assertEq(tAtlas.getPhase(), uint8(ExecutionPhase.FullyLocked), "phase should be FullyLocked");
    }

    function test_GasAccounting_updateAnalytics() public {
        EscrowAccountAccessData memory accountData = tAtlas.getAccessData(solverOneEOA);
        uint256 gasValueUsed = 100_000 * 1e9; // 100k gas * 1 gwei gas price

        uint256 snapshot = vm.snapshotState();

        // Case 1: Auction won
        EscrowAccountAccessData memory aDataAfter = tAtlas.updateAnalytics(accountData, true, gasValueUsed);

        assertEq(aDataAfter.auctionWins, accountData.auctionWins + 1, "auctionWins should increase by 1");
        assertEq(aDataAfter.auctionFails, accountData.auctionFails, "auctionFails should not change");
        assertEq(
            aDataAfter.totalGasValueUsed,
            accountData.totalGasValueUsed + 100_000,
            "totalGasValueUsed should increase by gasValueUsed/1e9"
        );

        // Case 2: Auction lost
        vm.revertToState(snapshot);

        aDataAfter = tAtlas.updateAnalytics(accountData, false, gasValueUsed);

        assertEq(aDataAfter.auctionWins, accountData.auctionWins, "auctionWins should not change");
        assertEq(aDataAfter.auctionFails, accountData.auctionFails + 1, "auctionFails should increase by 1");
        assertEq(
            aDataAfter.totalGasValueUsed,
            accountData.totalGasValueUsed + 100_000,
            "totalGasValueUsed should increase by gasValueUsed/1e9"
        );
    }

    function test_GasAccounting_isBalanceReconciled() public {
        // solverGasLiability = (1000 - 500) * (1 + surcharges) = 500 * 1.2 * 1e9 = 600 gwei
        // maxApprovedGasSpend = (600 gwei / tx.gasprice) as well
        GasLedger memory gL = GasLedger(1000, 0, 0, 500, 600); 
        BorrowsLedger memory bL; // starts (0, 0)
        tAtlas.setGasLedger(gL.pack());

        vm.txGasPrice(1e9); // set gas price to 1 gwei

        // NOTE: maxApprovedGasSpend stores gas units, so implicitly need to multiply by tx.gasprice when using
        assertEq(gL.maxApprovedGasSpend, 600, "maxApprovedGasSpend should start 600");
        assertEq(gL.solverGasLiability(A_SURCHARGE + B_SURCHARGE), 600 * tx.gasprice, "solverGasLiability should start 600 * tx.gasprice");

        // Case 1: borrows > repays | solver liability covered
        // --> should return false
        bL.borrows = 1e18;
        tAtlas.setBorrowsLedger(bL.pack());
        assertEq(tAtlas.isBalanceReconciled(), false, "borrows > repays should return false");

        // Case 2: borrows == repays == 0 | solver liability covered
        // --> should return true
        bL.borrows = 0;
        tAtlas.setBorrowsLedger(bL.pack());
        assertEq(tAtlas.isBalanceReconciled(), true, "borrows == repays == 0 should return true");

        // Case 3: repays > borrows | solver liability covered | should return true
        bL.borrows = 0;
        bL.repays = 1e18;
        tAtlas.setBorrowsLedger(bL.pack());
        assertEq(tAtlas.isBalanceReconciled(), true, "repays > borrows should return true");

        // Case 4: repays == borrows == 100 | solver liability not covered
        // --> should return false
        bL.borrows = 100;
        bL.repays = 100;
        gL.maxApprovedGasSpend = 0;
        tAtlas.setBorrowsLedger(bL.pack());
        tAtlas.setGasLedger(gL.pack());
        assertEq(tAtlas.isBalanceReconciled(), false, "uncovered solver liability should return false");

        // Case 5: repays - borrows = 300 gwei | maxApprovedGasSpend = 300 gwei | solver liability covered by combo
        // --> should return true
        bL.borrows = uint128(100 * tx.gasprice);
        bL.repays = uint128(400 * tx.gasprice);
        gL.maxApprovedGasSpend = 300; // will be multiplied by tx.gasprice to get gas value approved
        tAtlas.setBorrowsLedger(bL.pack());
        tAtlas.setGasLedger(gL.pack());
        assertEq(tAtlas.isBalanceReconciled(), true, "solver liability covered by combo should return true");
    }
}

/// @title TestAtlasGasAcc
/// @author FastLane Labs
/// @notice A test version of the Atlas contract that just exposes internal GasAccounting functions for testing.
contract TestAtlasGasAcc is TestAtlas {
    using GasAccLib for GasLedger;

    constructor(
        uint256 _escrowDuration,
        uint256 _atlasSurchargeRate,
        uint256 _bundlerSurchargeRate,
        address _verification,
        address _simulator,
        address _surchargeRecipient,
        address _l2GasCalculator,
        address _executionTemplate
    )
        TestAtlas(
            _escrowDuration,
            _atlasSurchargeRate,
            _bundlerSurchargeRate,
            _verification,
            _simulator,
            _surchargeRecipient,
            _l2GasCalculator,
            _executionTemplate
        )
    { }

    function initializeAccountingValues(uint256 gasMarker, uint256 allSolverOpsGas) public payable {
        _initializeAccountingValues(gasMarker, allSolverOpsGas);
    }

    // contribute() is already external
    // borrow() is already external
    // shortfall() is already external
    // reconcile() is already external

    function contribute_internal() public payable {
        _contribute();
    }

    function borrow_internal(uint256 borrowedAmount) public returns (bool) {
        return _borrow(borrowedAmount);
    }

    function assign(
        EscrowAccountAccessData memory accountData,
        address account,
        uint256 amount
    )
        public
        returns (uint256 deficit)
    {
        deficit = _assign(accountData, account, amount);

        // NOTE: only persisted to storage here for testing purposes
        S_accessData[account] = accountData;
    }

    function credit(
        EscrowAccountAccessData memory accountData,
        uint256 amount
    )
        public
        returns (EscrowAccountAccessData memory)
    {
        _credit(accountData, amount);

        // NOTE: only returned for testing purposes
        return accountData;
    }

    function handleSolverFailAccounting(
        SolverOperation calldata solverOp,
        uint256 dConfigSolverGasLimit,
        uint256 gasWaterMark,
        uint256 result,
        bool exPostBids
    )
        external
    {
        _handleSolverFailAccounting(solverOp, dConfigSolverGasLimit, gasWaterMark, result, exPostBids);
    }

    function writeOffBidFindGas(uint256 gasUsed) public {
        _writeOffBidFindGas(gasUsed);
    }

    function chargeUnreachedSolversForCalldata(
        SolverOperation[] calldata solverOps,
        GasLedger memory gL,
        uint256 solverIdx
    )
        public
        returns (uint256 unreachedCalldataValuePaid)
    {
        unreachedCalldataValuePaid = _chargeUnreachedSolversForCalldata(solverOps, gL, solverIdx);

        // NOTE: only persisted to storage here for testing purposes
        t_gasLedger = gL.pack();
    }

    function settle(
        Context memory ctx,
        GasLedger memory gL,
        uint256 gasMarker,
        address gasRefundBeneficiary,
        uint256 unreachedCalldataValuePaid,
        bool multipleSuccessfulSolvers
    ) public returns (uint256 claimsPaidToBundler, uint256 netAtlasGasSurcharge) {
        (claimsPaidToBundler, netAtlasGasSurcharge) = _settle(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid, multipleSuccessfulSolvers);
    }

    function updateAnalytics(
        EscrowAccountAccessData memory aData,
        bool auctionWon,
        uint256 gasValueUsed
    )
        public
        pure
        returns (EscrowAccountAccessData memory)
    {
        _updateAnalytics(aData, auctionWon, gasValueUsed);

        // NOTE: only returned for testing purposes
        return aData;
    }

    function isBalanceReconciled() public view returns (bool) {
        return _isBalanceReconciled();
    }

    function getAccessData(address account) public view returns (EscrowAccountAccessData memory) {
        return S_accessData[account];
    }
}
