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
    uint256 public constant ONE_GWEI = 1e9;

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
            DEFAULT_ATLAS_SURCHARGE_RATE,
            DEFAULT_BUNDLER_SURCHARGE_RATE,
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

        tAtlas.initializeAccountingValues{value: msgValue}(gasMarker, allSolverOpsGas);

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
        tAtlas.contribute{value: msgValue}();

        // Directly testing the internal _contribute() function:
        tAtlas.contribute_internal{value: msgValue}();

        BorrowsLedger memory bL = tAtlas.getBorrowsLedger();
        assertEq(bL.repays, msgValue, "repays should be msgValue");

        // If msg.value is 0, nothing should change
        tAtlas.contribute_internal{value: 0}();

        bL = tAtlas.getBorrowsLedger();
        assertEq(bL.repays, msgValue, "repays should still be msgValue");

        // Calling contribute_internal() again should increase repays again
        tAtlas.contribute_internal{value: msgValue}();
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
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InsufficientAtlETHBalance.selector, atlasStartBalance, atlasStartBalance + 1));
        tAtlas.borrow(atlasStartBalance + 1);

        // Case 6: Successful borrow sends ETH to the caller and increases borrows in BorrowLedger
        uint256 execEnvBalanceBefore = address(executionEnvironment).balance;
        BorrowsLedger memory bLBefore = tAtlas.getBorrowsLedger();

        vm.prank(executionEnvironment);
        tAtlas.borrow(borrowedAmount);

        BorrowsLedger memory bLAfter = tAtlas.getBorrowsLedger();
        assertEq(address(executionEnvironment).balance, execEnvBalanceBefore + borrowedAmount, "EE balance should increase by borrowedAmount");
        assertEq(address(tAtlas).balance, atlasStartBalance - borrowedAmount, "Atlas balance should decrease by borrowedAmount");
        assertEq(bLAfter.borrows, bLBefore.borrows + borrowedAmount, "Borrows should increase by borrowedAmount");
    }

    function test_GasAccounting_assign() public {
        vm.deal(solverOneEOA, 6e18); // 3 to unbonded, 2 unbonding, 1 bonded
        vm.startPrank(solverOneEOA);
        tAtlas.depositAndBond{value: 6e18}(3e18);
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
        vm.expectRevert(abi.encodeWithSelector(
            SafeCast.SafeCastOverflowedUintDowncast.selector, 112, uint256(type(uint112).max) + 1));
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
        vm.expectRevert(abi.encodeWithSelector(
            SafeCast.SafeCastOverflowedUintDowncast.selector, 112, uint256(type(uint112).max) + 1));
        tAtlas.credit(accountData, uint256(type(uint112).max) + 1);

        // Case 2: Should credit the account with the amount, and bondedTotalSupply should increase
        EscrowAccountAccessData memory  newAccData = tAtlas.credit(accountData, 1e18);

        assertEq(newAccData.bonded, accountData.bonded + 1e18, "accountData.bonded should increase by 1e18");
        assertEq(tAtlas.bondedTotalSupply(), 1e18, "bondedTotalSupply should be 1e18");
    }

    function test_GasAccounting_handleSolverFailAccounting() public {
        
    }

}


/// @title TestAtlasGasAcc
/// @author FastLane Labs
/// @notice A test version of the Atlas contract that just exposes internal GasAccounting functions for testing.
contract TestAtlasGasAcc is TestAtlas {
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
        TestAtlas(_escrowDuration, _atlasSurchargeRate, _bundlerSurchargeRate, _verification, _simulator, _surchargeRecipient, _l2GasCalculator, _executionTemplate)
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

    function borrow_internal(uint256 borrowedAmount) public returns(bool) {
        return _borrow(borrowedAmount);
    }

    function assign(
        EscrowAccountAccessData memory accountData,
        address account,
        uint256 amount
    ) public returns(uint256 deficit) {
        deficit = _assign(accountData, account, amount);

        // NOTE: only persisted to storage here for testing purposes
        S_accessData[account] = accountData;
    }

    function credit(
        EscrowAccountAccessData memory accountData,
        uint256 amount
    ) public returns(EscrowAccountAccessData memory) {
        _credit(accountData, amount);

        // NOTE: only returned for testing purposes
        return accountData;
    }

    function handleSolverFailAccounting(
        SolverOperation calldata solverOp,
        uint256 dConfigSolverGasLimit,
        uint256 gasWaterMark,
        uint256 result,
        bool includeCalldata
    ) public {
        _handleSolverFailAccounting(solverOp, dConfigSolverGasLimit, gasWaterMark, result, includeCalldata);
    }

    function writeOffBidFindGas(uint256 gasUsed) public {
        _writeOffBidFindGas(gasUsed);
    }

    function chargeUnreachedSolversForCalldata(
        SolverOperation[] calldata solverOps,
        GasLedger memory gL,
        uint256 solverIdx
    ) public returns(uint256 unreachedCalldataValuePaid) {
        unreachedCalldataValuePaid = _chargeUnreachedSolversForCalldata(solverOps, gL, solverIdx);
    }

    function settle(
        Context memory ctx,
        GasLedger memory gL,
        uint256 gasMarker,
        address gasRefundBeneficiary,
        uint256 unreachedCalldataValuePaid
    ) public returns (uint256 claimsPaidToBundler, uint256 netAtlasGasSurcharge) {
        (claimsPaidToBundler, netAtlasGasSurcharge) = _settle(ctx, gL, gasMarker, gasRefundBeneficiary, unreachedCalldataValuePaid);
    }

    function updateAnalytics(
        EscrowAccountAccessData memory aData,
        bool auctionWon,
        uint256 gasValueUsed
    ) public pure {
        _updateAnalytics(aData, auctionWon, gasValueUsed);
    }


    function isBalanceReconciled() public view returns (bool) {
        return _isBalanceReconciled();
    }

    function getAccessData(address account) public view returns (EscrowAccountAccessData memory) {
        return S_accessData[account];
    }
}