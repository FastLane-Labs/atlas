// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { Simulator, Result } from "../src/contracts/helpers/Simulator.sol";
import { DAppConfig, CallConfig } from "../src/contracts/types/ConfigTypes.sol";
import { DAppOperation } from "../src/contracts/types/DAppOperation.sol";
import { UserOperation } from "../src/contracts/types/UserOperation.sol";
import { SolverOperation } from "../src/contracts/types/SolverOperation.sol";
import { AtlasEvents } from "../src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "../src/contracts/types/AtlasErrors.sol";
import { ValidCallsResult } from "../src/contracts/types/ValidCalls.sol";
import { SolverOutcome } from "../src/contracts/types/EscrowTypes.sol";
import { CallVerification } from "../src/contracts/libraries/CallVerification.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";
import { CallConfigBuilder } from "./helpers/CallConfigBuilder.sol";
import { DummyDAppControlBuilder } from "./helpers/DummyDAppControlBuilder.sol";

import { DummyDAppControl } from "./base/DummyDAppControl.sol";
import { SolverBase } from "../src/contracts/solver/SolverBase.sol";

contract SimulatorTest is BaseTest {
    uint256 simBalanceBefore;
    DummyDAppControl dAppControl;
    
    struct ValidCallsCall {
        UserOperation userOp;
        SolverOperation[] solverOps;
        DAppOperation dAppOp;
        uint256 metacallGasLeft;
        uint256 msgValue;
        address msgSender;
        bool isSimulation;
    }

    function setUp() public override {
        BaseTest.setUp();
        dAppControl = defaultDAppControl().buildAndIntegrate(atlasVerification);
        simBalanceBefore = address(simulator).balance;
    }

    function test_estimateMetacallGasLimit() public {
        // C1: no solverOps -> total == calldata + exec
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        (uint256 calldataGas, uint256 executionGas) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        uint256 totalGasLimit1 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        assertEq(totalGasLimit1, calldataGas + executionGas, "C1: total != calldata + exec");

        // C2: one solverOp -> total == calldata + exec AND > than totalGasLimit1
        solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp).withData(new bytes(50)).build();
        (calldataGas, executionGas) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        uint256 totalGasLimit2 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        assertEq(totalGasLimit2, calldataGas + executionGas, "C2: total != calldata + exec");
        assertGt(totalGasLimit2, totalGasLimit1, "C2: totalGasLimit2 should be greater than totalGasLimit1");

        // C3: two solverOps -> total == calldata + exec AND > than totalGasLimit2
        solverOps = new SolverOperation[](2);
        solverOps[0] = validSolverOperation(userOp).withData(new bytes(50)).build();
        solverOps[1] = validSolverOperation(userOp).withData(new bytes(50)).build();
        (calldataGas, executionGas) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        uint256 totalGasLimit3 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        assertEq(totalGasLimit3, calldataGas + executionGas, "C3: total != calldata + exec");
        assertGt(totalGasLimit3, totalGasLimit2, "C3: totalGasLimit3 should be greater than totalGasLimit2");
        assertEq(totalGasLimit3 - totalGasLimit2, totalGasLimit2 - totalGasLimit1, "C3: gas difference should be constant");

        // C4: calldataGas increases when userOp.data length grows
        userOp.data = new bytes(100);
        (uint256 calldataGas1, uint256 executionGas1) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit1 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        userOp.data = new bytes(200);
        (uint256 calldataGas2, uint256 executionGas2) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit2 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        assertGt(calldataGas2, calldataGas1, "C4: calldataGas should increase with userOp.data length");
        assertEq(executionGas2, executionGas1, "C4: executionGas should not change with userOp.data length");
        assertGt(totalGasLimit2, totalGasLimit1, "C4: totalGasLimit2 should be greater than totalGasLimit1");

        // C5: calldataGas increases when solverOps data length grows
        solverOps = new SolverOperation[](1);
        solverOps[0].data = new bytes(100);
        (calldataGas1, executionGas1) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit1 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        solverOps[0].data = new bytes(200);
        (calldataGas2, executionGas2) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit2 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        assertGt(calldataGas2, calldataGas1, "C5: calldataGas should increase with solverOps data length");
        assertEq(executionGas2, executionGas1, "C5: executionGas should not change with solverOps data length");
        assertGt(totalGasLimit2, totalGasLimit1, "C5: totalGasLimit2 should be greater than totalGasLimit1");

        // C6: solverGasLimit cap (Math.min) is applied to executionGas
        solverOps[0].data = new bytes(50); // Reset data length
        solverOps[0].gas = 1_000_000; // 1 000 000 is the ceiling set by the DAppControl
        (, executionGas1) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit1 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        solverOps[0].gas = 2_000_000; // 2 000 000 is above the ceiling
        (, executionGas2) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit2 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        assertEq(executionGas1, executionGas2, "C6: executionGas should be capped by solverGasLimit");
        assertEq(totalGasLimit1, totalGasLimit2, "C6: totalGasLimits should be eq due to capped executionGas");

        // C7: If exPostBids = true, executionGas is increased by due to bid-finding solver gas and overhead
        dAppControl = defaultDAppControlWithCallConfig(
            defaultCallConfig().withExPostBids(true).build()
        ).buildAndIntegrate(atlasVerification);
        userOp = validUserOperation().withControl(address(dAppControl)).build();
        solverOps[0] = validSolverOperation(userOp)
            .withData(new bytes(50)) // Reset data length
            .withGas(1_000_000) // Reset gas limit to ceiling
            .build();
        (, executionGas2) = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);
        totalGasLimit2 = simulator.estimateMetacallGasLimit(userOp, solverOps);
        // Comparing exPostBids vars to C6 (normal) vars - executionGas1 and totalGasLimit1
        assertGt(executionGas2, executionGas1, "C7: executionGas should increase with exPostBids");
        assertGt(totalGasLimit2, totalGasLimit1, "C7: totalGasLimit should increase with exPostBids");
    }

    function test_metacallRecievesExecutionGasInSims() public {
        // Use MockAtlasSimReceiver in place of Atlas to intercept the gasleft event
        MockAtlasSimReceiver mockAtlas = new MockAtlasSimReceiver(address(0));
        vm.prank(deployer);
        simulator.setAtlas(address(mockAtlas));

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        userOp.data = new bytes(234); // Extra calldata to test gas estimation
        solverOps[0].data = new bytes(123);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        // C1: Check execution gas left in metacall is correct in simUserOperation()
        (, uint256 metacallExecutionGas)
            = simulator.estimateMetacallGasLimitComponents(userOp, new SolverOperation[](0));

        vm.recordLogs();
        (bool success, ) = address(simulator).call(
            abi.encodeCall(Simulator.simUserOperation, (userOp))
        );

        assertTrue(success, "C1: simUserOperation failed");
        Vm.Log[] memory events = vm.getRecordedLogs();
        assertEq(events.length, 1, "C1: Should have exactly one log");
        assertTrue(
            events[0].topics[0] == MockAtlasSimReceiver.MetacallGasLeft.selector,
            "C1: not MetacallGasLeft event"
        );
        uint256 gasLeft = abi.decode(events[0].data, (uint256));
        assertApproxEqRel(
            metacallExecutionGas, // Expected execution gas
            gasLeft, // Actual gas left in metacall
            0.01e18, // 1% tolerance
            "C1: incorrect metacall gasleft"
        );

        // C2: Check execution gas left in metacall is correct in simSolverCall()
        (, metacallExecutionGas)
            = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);

        vm.recordLogs();
        (success, ) = address(simulator).call(
            abi.encodeCall(Simulator.simSolverCall, (userOp, solverOps[0], dAppOp))
        );

        assertTrue(success, "C2: simSolverCall failed");
        events = vm.getRecordedLogs();
        assertEq(events.length, 1, "C2: Should have exactly one log");
        assertTrue(
            events[0].topics[0] == MockAtlasSimReceiver.MetacallGasLeft.selector,
            "C2: not MetacallGasLeft event"
        );
        gasLeft = abi.decode(events[0].data, (uint256));
        assertApproxEqRel(
            metacallExecutionGas, // Expected execution gas
            gasLeft, // Actual gas left in metacall
            0.01e18, // 1% tolerance
            "C2: incorrect metacall gasleft"
        );

        // C3: Check execution gas left in metacall is correct in simSolverCalls()
        solverOps = new SolverOperation[](2);
        solverOps[0] = validSolverOperation(userOp).withData(new bytes(246)).build();
        solverOps[1] = validSolverOperation(userOp).withData(new bytes(468)).build();
        dAppOp = validDAppOperation(userOp, solverOps).build();

        (, metacallExecutionGas)
            = simulator.estimateMetacallGasLimitComponents(userOp, solverOps);

        vm.recordLogs();
        (success, ) = address(simulator).call(
            abi.encodeCall(Simulator.simSolverCalls, (userOp, solverOps, dAppOp))
        );

        assertTrue(success, "C3: simSolverCalls failed");
        events = vm.getRecordedLogs();
        assertEq(events.length, 1, "C3: Should have exactly one log");
        assertTrue(
            events[0].topics[0] == MockAtlasSimReceiver.MetacallGasLeft.selector,
            "C3: not MetacallGasLeft event"
        );
        gasLeft = abi.decode(events[0].data, (uint256));
        assertApproxEqRel(
            metacallExecutionGas, // Expected execution gas
            gasLeft, // Actual gas left in metacall
            0.01e18, // 1% tolerance
            "C3: incorrect metacall gasleft"
        );
    }        

    function test_simUserOperation_success_valid_SkipCoverage() public {
        UserOperation memory userOp = validUserOperation().build();

        (bool success, Result result, uint256 validCallsResult) = simulator.simUserOperation(userOp);

        assertEq(success, true);
        assertTrue(uint(result) > uint(Result.UserOpSimFail)); // Actually fails with SolverSimFail here
        assertEq(validCallsResult, 0);
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simUserOperation_success_valid_UserOpValue_SkipCoverage() public {
        UserOperation memory userOp = validUserOperation()
            .withValue(1e18)
            .signAndBuild(address(atlasVerification), userPK);

        (bool success, Result result, uint256 validCallsResult) = simulator.simUserOperation(userOp);

        assertEq(success, true);
        assertTrue(uint(result) > uint(Result.UserOpSimFail)); // Actually fails with SolverSimFail here
        assertEq(validCallsResult, 0);
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simUserOperation_fail_bubblesUpValidCallsResult() public {
        UserOperation memory userOp = validUserOperation().withMaxFeePerGas(1).signAndBuild(address(atlasVerification), userPK);

        (bool success, Result result, uint256 validCallsResult) = simulator.simUserOperation(userOp);

        assertEq(success, false);
        assertEq(uint(result), uint(Result.VerificationSimFail));
        assertEq(validCallsResult, uint256(ValidCallsResult.GasPriceHigherThanMax));
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCall_success_validSolverOutcome_SkipCoverage() public {
        vm.startPrank(solverOneEOA);
        DummySolver solver = new DummySolver(WETH_ADDRESS, address(atlas));
        atlas.bond(1e18);
        vm.stopPrank();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withSolver(address(solver))
            .withData(abi.encodeWithSelector(solver.solverFunc.selector))
            .signAndBuild(address(atlasVerification), solverOnePK);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCall(userOp, solverOps[0], dAppOp);

        assertEq(success, true, "call should succeed");
        assertEq(uint(result), uint(Result.SimulationPassed), "result should be SimulationPassed");
        assertEq(solverOutcomeResult, 0, "solverOutcomeResult should be 0");
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCall_success_validSolverOutcome_UserOpValue_SkipCoverage() public {
        vm.startPrank(solverOneEOA);
        DummySolver solver = new DummySolver(WETH_ADDRESS, address(atlas));
        atlas.bond(1e18);
        vm.stopPrank();

        UserOperation memory userOp = validUserOperation()
            .withValue(1e18)
            .signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withSolver(address(solver))
            .withData(abi.encodeWithSelector(solver.solverFunc.selector))
            .signAndBuild(address(atlasVerification), solverOnePK);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCall(userOp, solverOps[0], dAppOp);

        assertEq(success, true);
        assertEq(uint(result), uint(Result.SimulationPassed));
        assertEq(solverOutcomeResult, 0);
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCall_fail_bubblesUpSolverOutcomeResult_SkipCoverage() public {
        vm.startPrank(solverOneEOA);
        DummySolver solver = new DummySolver(WETH_ADDRESS, address(atlas));
        // atlas.bond(1e18); - DO NOT BOND - Triggers InsufficientEscrow error
        vm.stopPrank();

        
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withSolver(address(solver))
            .withData(abi.encodeWithSelector(solver.solverFunc.selector))
            .signAndBuild(address(atlasVerification), solverOnePK);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCall(userOp, solverOps[0], dAppOp);

        assertEq(success, false, "call should fail");
        assertEq(uint(result), uint(Result.SolverSimFail), "result should be SolverSimFail");
        assertEq(solverOutcomeResult, 1 << uint256(SolverOutcome.InsufficientEscrow), "solverOutcomeResult should be InsufficientEscrow");
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCalls_success_validSolverOutcome_SkipCoverage() public {
        vm.startPrank(solverOneEOA);
        DummySolver solver = new DummySolver(WETH_ADDRESS, address(atlas));
        atlas.bond(1e18);
        vm.stopPrank();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withSolver(address(solver))
            .withData(abi.encodeWithSelector(solver.solverFunc.selector))
            .signAndBuild(address(atlasVerification), solverOnePK);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCalls(userOp, solverOps, dAppOp);

        assertEq(success, true);
        assertEq(uint(result), uint(Result.SimulationPassed));
        assertEq(solverOutcomeResult, 0);
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCalls_success_validSolverOutcome_UserOpValue_SkipCoverage() public {
        vm.startPrank(solverOneEOA);
        DummySolver solver = new DummySolver(WETH_ADDRESS, address(atlas));
        atlas.bond(1e18);
        vm.stopPrank();

        UserOperation memory userOp = validUserOperation()
            .withValue(1e18)
            .signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withSolver(address(solver))
            .withData(abi.encodeWithSelector(solver.solverFunc.selector))
            .signAndBuild(address(atlasVerification), solverOnePK);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCalls(userOp, solverOps, dAppOp);

        assertEq(success, true);
        assertEq(uint(result), uint(Result.SimulationPassed));
        assertEq(solverOutcomeResult, 0);
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCalls_fail_noSolverOps() public {
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCalls(userOp, solverOps, dAppOp);

        assertEq(success, false);
        assertEq(uint(result), uint(Result.Unknown)); // Should return Unknown if no solverOps given
        assertEq(solverOutcomeResult, uint256(type(SolverOutcome).max) + 1);
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    function test_simSolverCalls_fail_bubblesUpSolverOutcomeResult_SkipCoverage() public {
        vm.startPrank(solverOneEOA);
        DummySolver solver = new DummySolver(WETH_ADDRESS, address(atlas));
        // atlas.bond(1e18); - DO NOT BOND - Triggers InsufficientEscrow error
        vm.stopPrank();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withSolver(address(solver))
            .withData(abi.encodeWithSelector(solver.solverFunc.selector))
            .signAndBuild(address(atlasVerification), solverOnePK);
        DAppOperation memory dAppOp = validDAppOperation(userOp, solverOps).build();

        (bool success, Result result, uint256 solverOutcomeResult) = simulator.simSolverCalls(userOp, solverOps, dAppOp);

        assertEq(success, false);
        assertEq(uint(result), uint(Result.SolverSimFail));
        assertEq(solverOutcomeResult, 1 << uint256(SolverOutcome.InsufficientEscrow));
        assertEq(address(simulator).balance, simBalanceBefore, "Balance should not change");
    }

    // Deployer Function Tests

    function test_simulator_setAtlas() public {
        assertEq(simulator.atlas(), address(atlas));

        vm.expectRevert(AtlasErrors.Unauthorized.selector);
        simulator.setAtlas(address(0));
        assertEq(simulator.atlas(), address(atlas), "Should revert if not deployer");
        
        vm.prank(deployer);
        simulator.setAtlas(address(123));
        assertEq(simulator.atlas(), address(123), "Should set new atlas address");
    }

    function test_simulator_withdrawETH() public {
        address recipient = makeAddr("LuckyRecipient");
        uint256 recipientBalanceBefore = address(recipient).balance;
        simBalanceBefore = address(simulator).balance;
        

        vm.expectRevert(AtlasErrors.Unauthorized.selector);
        simulator.withdrawETH(recipient);
        assertEq(address(simulator).balance, simBalanceBefore, "Should revert if caller not deployer");

        vm.prank(deployer);
        simulator.withdrawETH(recipient);
        assertEq(address(simulator).balance, 0, "Should withdraw all balance");
        assertEq(address(recipient).balance, recipientBalanceBefore + simBalanceBefore, "Should send balance to recipient");
    }


    // Test Helpers

    function defaultCallConfig() public returns (CallConfigBuilder) {
        return new CallConfigBuilder();
    }

    function defaultDAppControl() public returns (DummyDAppControlBuilder) {
        return new DummyDAppControlBuilder()
            .withEscrow(address(atlas))
            .withGovernance(governanceEOA)
            .withCallConfig(defaultCallConfig().build());
    }

    function defaultDAppControlWithCallConfig(CallConfig memory callConfig) public returns (DummyDAppControlBuilder) {
        return new DummyDAppControlBuilder()
            .withEscrow(address(atlas))
            .withGovernance(governanceEOA)
            .withCallConfig(callConfig);
    }

    function validUserOperation() public returns (UserOperationBuilder) {
        return new UserOperationBuilder()
            .withFrom(userEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(tx.gasprice + 1)
            .withNonce(address(atlasVerification), userEOA)
            .withDeadline(block.number + 2)
            .withControl(address(dAppControl))
            .withCallConfig(dAppControl.CALL_CONFIG())
            .withDAppGasLimit(dAppControl.getDAppGasLimit())
            .withSolverGasLimit(dAppControl.getSolverGasLimit())
            .withBundlerSurchargeRate(dAppControl.getBundlerSurchargeRate())
            .withSessionKey(address(0))
            .withData("")
            .sign(address(atlasVerification), userPK);
    }

    function validSolverOperation(UserOperation memory userOp) public returns (SolverOperationBuilder) {
        return new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withData("")
            .withUserOpHash(userOp)
            .sign(address(atlasVerification), solverOnePK);
    }

    function validSolverOperations(UserOperation memory userOp) public returns (SolverOperation[] memory) {
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp).build();
        return solverOps;
    }

    function validDAppOperation(DAppConfig memory config, UserOperation memory userOp, SolverOperation[] memory solverOps) public returns (DAppOperationBuilder) {
        bytes32 callChainHash = CallVerification.getCallChainHash(userOp, solverOps);
        return new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withBundler(address(0))
            .withUserOpHash(userOp)
            .withCallChainHash(callChainHash)
            .sign(address(atlasVerification), governancePK);
    }

    function validDAppOperation(UserOperation memory userOp, SolverOperation[] memory solverOps) public returns (DAppOperationBuilder) {
        return new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withBundler(address(0))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK);
    }

}

contract MockAtlasSimReceiver {
    event MetacallGasLeft(uint256 gasLeft);

    address public immutable L2_GAS_CALCULATOR;

    uint256 public metacallGasLeft;

    constructor(address l2GasCalculator) {
        L2_GAS_CALCULATOR = l2GasCalculator;
    }

    function metacall(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        address gasRefundBeneficiary
    )
        external
        payable
        returns (bool)
    {
        emit MetacallGasLeft(gasleft());
        return true;
    }

    function getAtlasSurchargeRate() external view returns (uint256) {
        return 0; // Mock implementation, should return the surcharge rate
    }

}


contract DummySolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) { }
    function solverFunc() public { }
    fallback() external payable { }
    receive() external payable { }
}
