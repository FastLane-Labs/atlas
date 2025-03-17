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
        // TODO
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
    ) public returns(uint256) {
        return _assign(accountData, account, amount);
    }

    function credit(
        EscrowAccountAccessData memory accountData,
        uint256 amount
    ) public {
        _credit(accountData, amount);
    }

    function handleSolverFailAccounting(
        SolverOperation calldata solverOp,
        uint256 dConfigSolverGasLimit,
        uint256 gasWaterMark,
        uint256 result
    )
        external
    {
        _handleSolverFailAccounting(solverOp, dConfigSolverGasLimit, gasWaterMark, result);
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
}