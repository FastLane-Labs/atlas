// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { BaseTest } from "./base/BaseTest.t.sol";
import { MockSafetyLocks } from "./SafetyLocks.t.sol";

import { ExecutionEnvironment } from "src/contracts/atlas/ExecutionEnvironment.sol";
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

import { IFactory } from "src/contracts/interfaces/IFactory.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";

import { SolverBase } from "src/contracts/solver/SolverBase.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/LockTypes.sol";

import "src/contracts/libraries/CallBits.sol";

/// @notice ExecutionEnvironmentTest tests deploy ExecutionEnvironment contracts through the factory. Because all calls
/// are delegated through the mimic contract, the reported coverage is at 0%, but the actual coverage is close to 100%.
/// Non covered parts are explicitly mentioned in the comments, with the reason it couldn't be covered.
contract ExecutionEnvironmentTest is BaseTest {
    using stdStorage for StdStorage;
    using SafetyBits for EscrowKey;

    ExecutionEnvironment public executionEnvironment;
    MockDAppControl public dAppControl;

    EscrowKey public escrowKey;

    address public governance = makeAddr("governance");
    address public user = makeAddr("user");
    address public solver = makeAddr("solver");
    address public invalid = makeAddr("invalid");

    uint256 public lockSlot;
    uint256 public solverLockSlot;
    uint256 public depositsSlot;
    uint256 public claimsSlot;
    uint256 public withdrawalsSlot;

    CallConfig private callConfig;

    function setUp() public override {
        super.setUp();

        // Default setting for tests is all callConfig flags set to false.
        // For custom scenarios, set the needed flags and call setupDAppControl.
        setupDAppControl(callConfig);

        lockSlot = stdstore.target(address(atlas)).sig("lock()").find();
        solverLockSlot = lockSlot + 1;
        depositsSlot = stdstore.target(address(atlas)).sig("deposits()").find();
        claimsSlot = stdstore.target(address(atlas)).sig("claims()").find();
        withdrawalsSlot = stdstore.target(address(atlas)).sig("withdrawals()").find();
    }

    function _setLocks() internal {
        uint256 rawClaims = (gasleft() + 1) * tx.gasprice;
        rawClaims += ((rawClaims * 1_000_000) / 10_000_000);

        vm.store(address(atlas), bytes32(lockSlot), bytes32(uint256(uint160(address(executionEnvironment)))));
        vm.store(address(atlas), bytes32(solverLockSlot), bytes32(uint256(uint160(address(solver)))));
        vm.store(address(atlas), bytes32(depositsSlot), bytes32(uint256(msg.value)));
        vm.store(address(atlas), bytes32(claimsSlot), bytes32(uint256(rawClaims)));
        vm.store(address(atlas), bytes32(withdrawalsSlot), bytes32(uint256(0)));
    }

    function _unsetLocks() internal {
        vm.store(address(atlas), bytes32(lockSlot), bytes32(uint256(uint160(address(1)))));
        vm.store(address(atlas), bytes32(solverLockSlot), bytes32(uint256(1)));
        vm.store(address(atlas), bytes32(depositsSlot), bytes32(uint256(type(uint256).max)));
        vm.store(address(atlas), bytes32(claimsSlot), bytes32(uint256(type(uint256).max)));
        vm.store(address(atlas), bytes32(withdrawalsSlot), bytes32(uint256(type(uint256).max)));
    }

    function setupDAppControl(CallConfig memory customCallConfig) internal {
        vm.startPrank(governance);
        dAppControl = new MockDAppControl(address(atlas), governance, customCallConfig);
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
        vm.expectRevert(AtlasErrors.InvalidUser.selector);
        (status,) = address(executionEnvironment).call(preOpsData);

        // InvalidTo
        userOp.from = user;
        userOp.to = invalid; // Invalid to
        escrowKey = escrowKey.holdPreOpsLock(address(dAppControl));
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.InvalidTo.selector);
        (status,) = address(executionEnvironment).call(preOpsData);
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
        vm.expectRevert(AtlasErrors.OnlyAtlas.selector);
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert OnlyAtlas: call did not revert");

        // WrongPhase
        escrowKey = escrowKey.holdUserLock(address(dAppControl)); // Invalid lock state
        preOpsData = abi.encodeWithSelector(executionEnvironment.preOpsWrapper.selector, userOp);
        preOpsData = abi.encodePacked(preOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.WrongPhase.selector);
        (status,) = address(executionEnvironment).call(preOpsData);
        assertTrue(status, "expectRevert WrongPhase: call did not revert");

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
        vm.expectRevert(AtlasErrors.InvalidCodeHash.selector);
        (status,) = address(executionEnvironment).call(userData);
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
        vm.expectRevert(AtlasErrors.PreOpsDelegatecallFail.selector);
        (status,) = address(executionEnvironment).call(preOpsData);
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
        vm.expectRevert(AtlasErrors.UserOpValueExceedsBalance.selector);
        (status,) = address(executionEnvironment).call(userData);
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
        vm.expectRevert(AtlasErrors.UserWrapperCallFail.selector);
        (status,) = address(executionEnvironment).call(userData);

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
        vm.expectRevert(AtlasErrors.UserWrapperDelegatecallFail.selector);
        (status,) = address(executionEnvironment).call(userData);
    }

    function test_postOpsWrapper() public {
        bytes memory postOpsData;
        bool status;

        // Valid
        escrowKey.addressPointer = address(dAppControl);
        escrowKey.callCount = 4;
        escrowKey = escrowKey.holdPostOpsLock();
        postOpsData =
            abi.encodeWithSelector(executionEnvironment.postOpsWrapper.selector, false, abi.encode(false, true));
        postOpsData = abi.encodePacked(postOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(postOpsData);
        assertTrue(status);

        // DelegateRevert
        escrowKey = escrowKey.holdPostOpsLock();
        postOpsData =
            abi.encodeWithSelector(executionEnvironment.postOpsWrapper.selector, false, abi.encode(true, false));
        postOpsData = abi.encodePacked(postOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.PostOpsDelegatecallFail.selector);
        (status,) = address(executionEnvironment).call(postOpsData);

        // DelegateUnsuccessful
        escrowKey = escrowKey.holdPostOpsLock();
        postOpsData =
            abi.encodeWithSelector(executionEnvironment.postOpsWrapper.selector, false, abi.encode(false, false));
        postOpsData = abi.encodePacked(postOpsData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.PostOpsDelegatecallReturnedFalse.selector);
        (status,) = address(executionEnvironment).call(postOpsData);
    }

    /*
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
        _setLocks();
        solverOp.value = 1; // Positive value but EE has no balance
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverOp.bidAmount, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.SolverMetaTryCatchIncorrectValue.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        solverOp.value = 0;
        _unsetLocks();

        // AlteredControl
        _setLocks();
        solverOp.control = invalid; // Invalid control
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverOp.bidAmount, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.AlteredControl.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        solverOp.control = address(dAppControl);
        _unsetLocks();

        // SolverOperationReverted
        _setLocks();
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, true);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverOp.bidAmount, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.SolverOperationReverted.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        _unsetLocks();

        // SolverBidUnpaid
        _setLocks();
        solverOp.bidAmount = 1; // Bid won't be paid
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverOp.bidAmount, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.SolverBidUnpaid.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        solverOp.bidAmount = 0;
        _unsetLocks();

        // BalanceNotReconciled
        // Solver's contract does not call reconcile
        _setLocks();
        solverContract.setReconcile(false);
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector, solverOp.bidAmount, solverGasLimit, solverOp, new bytes(0)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.BalanceNotReconciled.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        solverContract.setReconcile(true);
        _unsetLocks();

        // Change of config
        callConfig.preSolver = true;
        setupDAppControl(callConfig);
        solverOp.control = address(dAppControl);

        // PreSolverFailed
        _setLocks();
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector,
            solverOp.bidAmount,
            solverGasLimit,
            solverOp,
            abi.encode(true, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.PreSolverFailed.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        _unsetLocks();

        // PreSolverFailed 2
        _setLocks();
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector,
            solverOp.bidAmount,
            solverGasLimit,
            solverOp,
            abi.encode(false, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.PreSolverFailed.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        _unsetLocks();

        // Change of config
        callConfig.preSolver = false;
        callConfig.postSolver = true;
        setupDAppControl(callConfig);
        solverOp.control = address(dAppControl);

        // PostSolverFailed
        _setLocks();
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector,
            solverOp.bidAmount,
            solverGasLimit,
            solverOp,
            abi.encode(true, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.PostSolverFailed.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        _unsetLocks();

        // IntentUnfulfilled
        _setLocks();
        solverOp.data = abi.encodeWithSelector(solverContract.solverMockOperation.selector, false);
        escrowKey = escrowKey.holdSolverLock(solverOp.solver);
        solverMetaData = abi.encodeWithSelector(
            executionEnvironment.solverMetaTryCatch.selector,
            solverOp.bidAmount,
            solverGasLimit,
            solverOp,
            abi.encode(false, false)
        );
        solverMetaData = abi.encodePacked(solverMetaData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.IntentUnfulfilled.selector);
        (status,) = address(executionEnvironment).call(solverMetaData);
        _unsetLocks();
    }
    */

    
    function test_allocateValue() public {
        bytes memory allocateData;
        bool status;

        // Valid
        escrowKey = escrowKey.holdAllocateValueLock(address(dAppControl));
        allocateData = abi.encodeWithSelector(
            executionEnvironment.allocateValue.selector, address(0), uint256(0), abi.encode(false)
        );
        allocateData = abi.encodePacked(allocateData, escrowKey.pack());
        vm.prank(address(atlas));
        (status,) = address(executionEnvironment).call(allocateData);
        assertTrue(status);

        // DelegateRevert
        escrowKey = escrowKey.holdAllocateValueLock(address(dAppControl));
        allocateData = abi.encodeWithSelector(
            executionEnvironment.allocateValue.selector, address(0), uint256(0), abi.encode(true)
        );
        allocateData = abi.encodePacked(allocateData, escrowKey.pack());
        vm.prank(address(atlas));
        vm.expectRevert(AtlasErrors.AllocateValueDelegatecallFail.selector);
        (status,) = address(executionEnvironment).call(allocateData);
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
        vm.expectRevert(AtlasErrors.NotEnvironmentOwner.selector);
        executionEnvironment.withdrawERC20(chain.weth, 2e18);

        // BalanceTooLow
        vm.prank(user);
        vm.expectRevert(AtlasErrors.ExecutionEnvironmentBalanceTooLow.selector);
        executionEnvironment.withdrawERC20(chain.weth, 2e18);

        // The following line changes an Atlas storage value in order to make the test succeed.
        // lock value is normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to comment it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(lockSlot), bytes32(uint256(uint160(address(executionEnvironment)))));

        // EscrowLocked
        vm.prank(user);
        vm.expectRevert(AtlasErrors.AtlasLockActive.selector);
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
        vm.expectRevert(AtlasErrors.NotEnvironmentOwner.selector);
        executionEnvironment.withdrawEther(2e18);

        // BalanceTooLow
        vm.prank(user);
        vm.expectRevert(AtlasErrors.ExecutionEnvironmentBalanceTooLow.selector);
        executionEnvironment.withdrawEther(2e18);

        // The following line changes an Atlas storage value in order to make the test succeed.
        // lock value is normally initialized in the _initializeEscrowLock function,
        // but we can't call it in the current setup.
        // Any changes in the Storage contract could make this test fail, feel free to comment it until
        // the contract's layout is finalized.

        // Set lock address to the execution environment
        vm.store(address(atlas), bytes32(lockSlot), bytes32(uint256(uint160(address(executionEnvironment)))));

        // EscrowLocked
        vm.prank(user);
        vm.expectRevert(AtlasErrors.AtlasLockActive.selector);
        executionEnvironment.withdrawEther(2e18);
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
        assertEq(executionEnvironment.getEscrow(), address(atlas));
    }
}

contract MockDAppControl is DAppControl {
    constructor(
        address _atlas,
        address _governance,
        CallConfig memory _callConfig
    )
        DAppControl(_atlas, _governance, _callConfig)
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

    function _preSolverCall(
        SolverOperation calldata,
        bytes calldata returnData
    )
        internal
        pure
        override
    {
        (bool shouldRevert, bool returnValue) = abi.decode(returnData, (bool, bool));
        require(!shouldRevert, "_preSolverCall revert requested");
        if (!returnValue) revert("_preSolverCall returned false");
    }

    function _postSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        internal
        pure
        override
    {
        (bool shouldRevert, bool returnValue) = abi.decode(returnData, (bool, bool));
        require(!shouldRevert, "_postSolverCall revert requested");
        if (!returnValue) revert("_postSolverCall returned false");
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
    address private immutable _atlas;
    bool public shouldReconcile = true;

    constructor(address weth, address atlas) {
        WETH_ADDRESS = weth;
        _atlas = atlas;
    }

    function atlasSolverCall(
        address solverOpFrom,
        address executionEnvironment,
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
        if (shouldReconcile) {
            IEscrow(address(_atlas)).reconcile(executionEnvironment, solverOpFrom, type(uint256).max);
        }
    }

    function solverMockOperation(bool shouldRevert) public pure {
        require(!shouldRevert, "solverMockOperation revert requested");
    }

    function setReconcile(bool _shouldReconcile) external {
        shouldReconcile = _shouldReconcile;
    }
}
