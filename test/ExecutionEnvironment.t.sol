// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

import { ExecutionEnvironment } from "src/contracts/atlas/ExecutionEnvironment.sol";
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

import { IFactory } from "src/contracts/interfaces/IFactory.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";

import { SolverBase } from "src/contracts/solver/SolverBase.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { FastLaneErrorsEvents } from "src/contracts/types/Emissions.sol";

import "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/LockTypes.sol";

import "src/contracts/libraries/CallBits.sol";

/// @notice ExecutionEnvironmentTest tests deploy ExecutionEnvironment contracts through the factory. Because all calls
/// are delegated through the mimic contract, the reported coverage is at 0%, but the actual coverage is close to 100%.
/// Non covered parts are explicitly mentioned in the comments, with the reason it couldn't be covered.
contract ExecutionEnvironmentTest is BaseTest {
    using SafetyBits for EscrowKey;

    ExecutionEnvironment public executionEnvironment;
    MockDAppControl public dAppControl;

    EscrowKey public escrowKey;

    address public governance = makeAddr("governance");
    address public user = makeAddr("user");
    address public solver = makeAddr("solver");
    address public invalid = makeAddr("invalid");

    CallConfig private callConfig;

    function setUp() public override {
        super.setUp();

        // Default setting for tests is all callConfig flags set to false.
        // For custom scenarios, set the needed flags and call setupDAppControl.
        setupDAppControl(callConfig);
    }

    function setupDAppControl(CallConfig memory customCallConfig) internal {
        vm.startPrank(governance);
        dAppControl = new MockDAppControl(escrow, governance, customCallConfig);
        atlasVerification.initializeGovernance(address(dAppControl));
        vm.stopPrank();

        vm.prank(user);
        executionEnvironment =
            ExecutionEnvironment(payable(IFactory(address(atlas)).createExecutionEnvironment(address(dAppControl))));
    }

    function test_modifier_validUser() public {
        UserOperation memory userOp;
        bytes memory preOpsData;
        bool status;

        // Valid
        userOp.from = user;
        userOp.to = address(atlas);
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status);

        // InvalidUser
        userOp.from = invalid; // Invalid from
        userOp.to = address(atlas);
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-CE02 InvalidUser"));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert ERR-CE02 InvalidUser: call did not revert");

        // InvalidTo
        userOp.from = user;
        userOp.to = invalid; // Invalid to
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EV007 InvalidTo"));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert ERR-EV007 InvalidTo: call did not revert");
    }

    function test_modifier_onlyAtlasEnvironment() public {
        UserOperation memory userOp;
        bytes memory preOpsData;
        bool status;

        userOp.from = user;
        userOp.to = address(atlas);

        // Valid
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status);

        // InvalidSender
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(0)); // Invalid sender
        vm.expectRevert(bytes("ERR-EB01 InvalidSender"));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert ERR-EB01 InvalidSender: call did not revert");

        // WrongPhase
        escrowKey = escrowKey.holdUserLock(address(dAppControl)); // Invalid lock state
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EB02 WrongPhase"));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert ERR-EB02 WrongPhase: call did not revert");

        // NotDelegated and WrongDepth
        // Can't be reached with this setup.
        // Tests for Base contract (where this modifier is defined) should cover those reverts.
    }

    function test_modifier_validControlHash() public {
        UserOperation memory userOp;
        bytes memory userData;
        bool status;

        userOp.from = user;
        userOp.to = address(atlas);

        // Valid
        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(userData);
        assertTrue(status);

        // InvalidCodeHash
        // Alter the code hash of the control contract
        vm.etch(address(dAppControl), address(atlas).code);

        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EV008 InvalidCodeHash"));
        (status,) = address(executionEnvironment).call(userData);
        assertTrue(status, "expectRevert ERR-EV008 InvalidCodeHash: call did not revert");
    }

    function test_modifier_contributeSurplus() public {
        UserOperation memory userOp;
        bytes memory userData;
        bool status;

        userOp.from = user;
        userOp.to = address(atlas);

        // The following 2 lines change Atlas' storage values in order to make the test succeed.
        // lock and deposits values are normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to skip it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(uint256(8)), bytes32(uint256(uint160(address(executionEnvironment)))));
        // Set deposits to 0
        vm.store(address(atlas), bytes32(uint256(12)), bytes32(uint256(0)));

        uint256 depositsBefore = atlas.deposits();
        uint256 surplusAmount = 50_000;

        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call{ value: surplusAmount }(userData);
        assertTrue(status);
        assertEq(atlas.deposits(), depositsBefore + surplusAmount);
    }

    function test_preOpsWrapper() public {
        UserOperation memory userOp;
        bytes memory preOpsData;
        bool status;
        bytes memory data;

        userOp.from = user;
        userOp.to = address(atlas);
        userOp.dapp = address(dAppControl);

        // Valid
        uint256 expectedReturnValue = 123;
        userOp.data = abi.encodeWithSelector(dAppControl.mockOperation.selector, false, expectedReturnValue);
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        (status, data) = address(executionEnvironment).call(preOpsData);
        assertTrue(status);
        assertEq(abi.decode(abi.decode(data, (bytes)), (uint256)), expectedReturnValue);

        // DelegateRevert
        userOp.data = abi.encodeWithSelector(dAppControl.mockOperation.selector, true, uint256(0));
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC02 DelegateRevert"));
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert ERR-EC02 DelegateRevert: call did not revert");
    }

    function test_userWrapper() public {
        UserOperation memory userOp;
        bytes memory userData;
        bool status;
        bytes memory data;
        uint256 expectedReturnValue;

        userOp.from = user;
        userOp.to = address(atlas);
        userOp.dapp = address(dAppControl);

        // ValueExceedsBalance
        userOp.value = 1; // Positive value but EE has no balance
        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-CE01 ValueExceedsBalance"));
        (status,) = address(executionEnvironment).call(userData);
        assertTrue(status, "expectRevert ERR-CE01 ValueExceedsBalance: call did not revert");
        userOp.value = 0;

        // Valid (needsDelegateUser=false)
        expectedReturnValue = 987;
        userOp.data = abi.encodeWithSelector(dAppControl.mockOperation.selector, false, expectedReturnValue);
        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        (status, data) = address(executionEnvironment).call(userData);
        assertTrue(status);
        assertEq(abi.decode(abi.decode(data, (bytes)), (uint256)), expectedReturnValue);

        // CallRevert (needsDelegateUser=false)
        userOp.data = abi.encodeWithSelector(dAppControl.mockOperation.selector, true, 0);
        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC04a CallRevert"));
        (status,) = address(executionEnvironment).call(userData);
        assertTrue(status, "expectRevert ERR-EC04a CallRevert: call did not revert");

        // Change of config
        callConfig.delegateUser = true;
        setupDAppControl(callConfig);
        userOp.dapp = address(dAppControl);

        // Valid (needsDelegateUser=true)
        expectedReturnValue = 277;
        userOp.data = abi.encodeWithSelector(dAppControl.mockOperation.selector, false, expectedReturnValue);
        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        (status, data) = address(executionEnvironment).call(userData);
        assertTrue(status);
        assertEq(abi.decode(abi.decode(data, (bytes)), (uint256)), expectedReturnValue);

        // DelegateRevert (needsDelegateUser=true)
        userOp.data = abi.encodeWithSelector(dAppControl.mockOperation.selector, true, 0);
        escrowKey = escrowKey.holdUserLock(address(dAppControl));
        userData = abi.encodeWithSelector(executionEnvironment.userWrapper.selector, userOp);
        userData = abi.encodePacked(userData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC02 DelegateRevert"));
        (status,) = address(executionEnvironment).call(userData);
        assertTrue(status, "expectRevert ERR-EC02 DelegateRevert: call did not revert");
    }

    function test_postOpsWrapper() public {
        bytes memory postOpsData;
        bool status;

        // Valid
        escrowKey = escrowKey.holdDAppOperationLock(address(dAppControl));
        postOpsData =
            abi.encodeWithSelector(executionEnvironment.postOpsWrapper.selector, false, abi.encode(false, true));
        postOpsData = abi.encodePacked(postOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(postOpsData);
        assertTrue(status);

        // DelegateRevert
        escrowKey = escrowKey.holdDAppOperationLock(address(dAppControl));
        postOpsData =
            abi.encodeWithSelector(executionEnvironment.postOpsWrapper.selector, false, abi.encode(true, false));
        postOpsData = abi.encodePacked(postOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC02 DelegateRevert"));
        (status,) = address(executionEnvironment).call(postOpsData);
        assertTrue(status, "expectRevert ERR-EC02 DelegateRevert: call did not revert");

        // DelegateUnsuccessful
        escrowKey = escrowKey.holdDAppOperationLock(address(dAppControl));
        postOpsData =
            abi.encodeWithSelector(executionEnvironment.postOpsWrapper.selector, false, abi.encode(false, false));
        postOpsData = abi.encodePacked(postOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC03a DelegateUnsuccessful"));
        (status,) = address(executionEnvironment).call(postOpsData);
        assertTrue(status, "expectRevert ERR-EC03a DelegateUnsuccessful: call did not revert");
    }

    function test_solverMetaTryCatch() public {
        bytes memory solverMetaData;
        bool status;

        vm.prank(solver);
        MockSolverContract solverContract = new MockSolverContract(chain.weth, address(atlas));

        SolverOperation memory solverOp;
        solverOp.from = solver;
        solverOp.control = address(dAppControl);
        solverOp.solver = address(solverContract);

        uint256 solverGasLimit = 1_000_000;

        // IncorrectValue
        solverOp.value = 1; // Positive value but EE has no balance
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-CE05 IncorrectValue"));
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert ERR-CE05 IncorrectValue: call did not revert");
        solverOp.value = 0;

        // AlteredControlHash
        solverOp.control = invalid; // Invalid control
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.AlteredControlHash.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert AlteredControlHash: call did not revert");
        solverOp.control = address(dAppControl);

        // SolverOperationReverted
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, true);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.SolverOperationReverted.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert SolverOperationReverted: call did not revert");

        // SolverBidUnpaid
        solverOp.bidAmount = 1; // Bid won't be paid
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.SolverBidUnpaid.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert SolverBidUnpaid: call did not revert");
        solverOp.bidAmount = 0;

        // SolverMsgValueUnpaid
        // Solver's contract does not call reconcile
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.SolverMsgValueUnpaid.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert SolverMsgValueUnpaid: call did not revert");

        // Change of config
        callConfig.preSolver = true;
        setupDAppControl(callConfig);
        solverOp.control = address(dAppControl);

        // PreSolverFailed
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, abi.encode(true, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.PreSolverFailed.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert PreSolverFailed: call did not revert");

        // PreSolverFailed 2
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, abi.encode(false, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.PreSolverFailed.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert PreSolverFailed 2: call did not revert");

        // Change of config
        callConfig.preSolver = false;
        callConfig.postSolver = true;
        setupDAppControl(callConfig);
        solverOp.control = address(dAppControl);

        // PostSolverFailed
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, abi.encode(true, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.PostSolverFailed.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert PostSolverFailed: call did not revert");

        // IntentUnfulfilled
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverGasLimit, solverOp, abi.encode(false, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(FastLaneErrorsEvents.IntentUnfulfilled.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        assertTrue(status, "expectRevert IntentUnfulfilled: call did not revert");
    }

    function test_allocateValue() public {
        bytes memory allocateData;
        bool status;

        // Valid
        escrowKey = escrowKey.turnSolverLockPayments(address(dAppControl));
        allocateData = abi.encodeWithSelector(
            executionEnvironment.allocateValue.selector, address(0), uint256(0), abi.encode(false)
        );
        allocateData = abi.encodePacked(allocateData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(allocateData);
        assertTrue(status);

        // DelegateRevert
        escrowKey = escrowKey.turnSolverLockPayments(address(dAppControl));
        allocateData = abi.encodeWithSelector(
            executionEnvironment.allocateValue.selector, address(0), uint256(0), abi.encode(true)
        );
        allocateData = abi.encodePacked(allocateData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC02 DelegateRevert"));
        (status,) = address(executionEnvironment).call(allocateData);
        assertTrue(status, "expectRevert ERR-EC02 DelegateRevert: call did not revert");
    }

    function test_withdrawERC20() public {
        // Valid
        deal(chain.weth, address(executionEnvironment), 2e18);
        assertEq(ERC20(chain.weth).balanceOf(address(executionEnvironment)), 2e18);
        assertEq(ERC20(chain.weth).balanceOf(user), 0);
        vm.prank(user);
        executionEnvironment.withdrawERC20(chain.weth, 2e18);
        assertEq(ERC20(chain.weth).balanceOf(address(executionEnvironment)), 0);
        assertEq(ERC20(chain.weth).balanceOf(user), 2e18);

        // NotEnvironmentOwner
        vm.prank(invalid); // Invalid caller
        vm.expectRevert(bytes("ERR-EC01 NotEnvironmentOwner"));
        executionEnvironment.withdrawERC20(chain.weth, 2e18);

        // BalanceTooLow
        vm.prank(user);
        vm.expectRevert(bytes("ERR-EC02 BalanceTooLow"));
        executionEnvironment.withdrawERC20(chain.weth, 2e18);

        // The following line changes an Atlas storage value in order to make the test succeed.
        // lock value is normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to comment it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(uint256(8)), bytes32(uint256(uint160(address(executionEnvironment)))));

        // EscrowLocked
        vm.prank(user);
        vm.expectRevert(bytes("ERR-EC15 EscrowLocked"));
        executionEnvironment.withdrawERC20(chain.weth, 2e18);
    }

    function test_withdrawEther() public {
        // Valid
        deal(address(executionEnvironment), 2e18);
        assertEq(address(executionEnvironment).balance, 2e18);
        assertEq(user.balance, 0);
        vm.prank(user);
        executionEnvironment.withdrawEther(2e18);
        assertEq(address(executionEnvironment).balance, 0);
        assertEq(user.balance, 2e18);

        // NotEnvironmentOwner
        vm.prank(address(0)); // Invalid caller
        vm.expectRevert(bytes("ERR-EC01 NotEnvironmentOwner"));
        executionEnvironment.withdrawEther(2e18);

        // BalanceTooLow
        vm.prank(user);
        vm.expectRevert(bytes("ERR-EC03 BalanceTooLow"));
        executionEnvironment.withdrawEther(2e18);

        // The following line changes an Atlas storage value in order to make the test succeed.
        // lock value is normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to comment it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(uint256(8)), bytes32(uint256(uint160(address(executionEnvironment)))));

        // EscrowLocked
        vm.prank(user);
        vm.expectRevert(bytes("ERR-EC15 EscrowLocked"));
        executionEnvironment.withdrawEther(2e18);
    }

    function test_factoryWithdrawERC20() public {
        // Valid
        deal(chain.weth, address(executionEnvironment), 2e18);
        assertEq(ERC20(chain.weth).balanceOf(address(executionEnvironment)), 2e18);
        assertEq(ERC20(chain.weth).balanceOf(user), 0);
        vm.prank(address(atlas));
        executionEnvironment.factoryWithdrawERC20(user, chain.weth, 2e18);
        assertEq(ERC20(chain.weth).balanceOf(address(executionEnvironment)), 0);
        assertEq(ERC20(chain.weth).balanceOf(user), 2e18);

        // NotFactory
        vm.prank(invalid); // Invalid caller
        vm.expectRevert(bytes("ERR-EC10 NotFactory"));
        executionEnvironment.factoryWithdrawERC20(user, chain.weth, 2e18);

        // NotEnvironmentOwner
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC11 NotEnvironmentOwner"));
        executionEnvironment.factoryWithdrawERC20(invalid, chain.weth, 2e18); // Invalid user

        // BalanceTooLow
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC02 BalanceTooLow"));
        executionEnvironment.factoryWithdrawERC20(user, chain.weth, 2e18);

        // The following line changes an Atlas storage value in order to make the test succeed.
        // lock value is normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to comment it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(uint256(8)), bytes32(uint256(uint160(address(executionEnvironment)))));

        // EscrowLocked
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC15 EscrowLocked"));
        executionEnvironment.factoryWithdrawERC20(user, chain.weth, 2e18);
    }

    function test_factoryWithdrawEther() public {
        // Valid
        deal(address(executionEnvironment), 2e18);
        assertEq(address(executionEnvironment).balance, 2e18);
        assertEq(user.balance, 0);
        vm.prank(address(atlas));
        executionEnvironment.factoryWithdrawEther(user, 2e18);
        assertEq(address(executionEnvironment).balance, 0);
        assertEq(user.balance, 2e18);

        // NotFactory
        vm.prank(invalid); // Invalid caller
        vm.expectRevert(bytes("ERR-EC10 NotFactory"));
        executionEnvironment.factoryWithdrawEther(user, 2e18);

        // NotEnvironmentOwner
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC11 NotEnvironmentOwner"));
        executionEnvironment.factoryWithdrawEther(invalid, 2e18); // Invalid user

        // BalanceTooLow
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC03 BalanceTooLow"));
        executionEnvironment.factoryWithdrawEther(user, 2e18);

        // The following line changes an Atlas storage value in order to make the test succeed.
        // lock value is normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to comment it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(uint256(8)), bytes32(uint256(uint160(address(executionEnvironment)))));

        // EscrowLocked
        vm.prank(address(atlas));
        vm.expectRevert(bytes("ERR-EC15 EscrowLocked"));
        executionEnvironment.factoryWithdrawEther(user, 2e18);
    }

    function test_getUser() public {
        assertEq(executionEnvironment.getUser(), user);
    }

    function test_getControl() public {
        assertEq(executionEnvironment.getControl(), address(dAppControl));
    }

    function test_getConfig() public {
        assertEq(executionEnvironment.getConfig(), CallBits.encodeCallConfig(callConfig));
    }

    function test_getEscrow() public {
        assertEq(executionEnvironment.getEscrow(), escrow);
    }
}

contract MockDAppControl is DAppControl {
    constructor(
        address _escrow,
        address _governance,
        CallConfig memory _callConfig
    )
        DAppControl(_escrow, _governance, _callConfig)
    { }

    /*//////////////////////////////////////////////////////////////
                        ATLAS OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _preOpsCall(UserOperation calldata userOp) internal override returns (bytes memory) {
        if (userOp.data.length > 0) {
            (bool success, bytes memory data) = address(userOp.dapp).call(userOp.data);
            require(success, "_preOpsCall reverted");
            return data;
        }
        return new bytes(0);
    }

    function _postOpsCall(bool, bytes calldata data) internal pure override returns (bool) {
        (bool shouldRevert, bool returnValue) = abi.decode(data, (bool, bool));
        require(!shouldRevert, "_postSolverCall revert requested");
        return returnValue;
    }

    function _preSolverCall(bytes calldata data) internal pure override returns (bool) {
        (,, bytes memory dAppReturnData) = abi.decode(data, (address, uint256, bytes));
        (bool shouldRevert, bool returnValue) = abi.decode(dAppReturnData, (bool, bool));
        require(!shouldRevert, "_preSolverCall revert requested");
        return returnValue;
    }

    function _postSolverCall(bytes calldata data) internal pure override returns (bool) {
        (,, bytes memory dAppReturnData) = abi.decode(data, (address, uint256, bytes));
        (bool shouldRevert, bool returnValue) = abi.decode(dAppReturnData, (bool, bool));
        require(!shouldRevert, "_postSolverCall revert requested");
        return returnValue;
    }

    function _allocateValueCall(address, uint256, bytes calldata data) internal virtual override {
        (bool shouldRevert) = abi.decode(data, (bool));
        require(!shouldRevert, "_allocateValueCall revert requested");
    }

    function getBidFormat(UserOperation calldata) public view virtual override returns (address) { }
    function getBidValue(SolverOperation calldata) public view virtual override returns (uint256) { }

    /*//////////////////////////////////////////////////////////////
                            CUSTOM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mockOperation(bool shouldRevert, uint256 returnValue) public pure returns (uint256) {
        require(!shouldRevert, "mockOperation revert requested");
        return returnValue;
    }
}

contract MockSolverContract {
    address public immutable WETH_ADDRESS;
    address private immutable _escrow;

    constructor(address weth, address atlasEscrow) {
        WETH_ADDRESS = weth;
        _escrow = atlasEscrow;
    }

    function atlasSolverCall(
        address,
        address,
        uint256,
        bytes calldata solverOpData,
        bytes calldata
    )
        external
        payable
        returns (bool success, bytes memory data)
    {
        (success, data) = address(this).call{ value: msg.value }(solverOpData);
        require(success, "atlasSolverCall call reverted");
    }

    function solverMockOperation(bool shouldRevert) public pure {
        require(!shouldRevert, "solverMockOperation revert requested");
    }
}
