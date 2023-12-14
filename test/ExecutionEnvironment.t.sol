// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

import { ExecutionEnvironment } from "../src/contracts/atlas/ExecutionEnvironment.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";

import { IFactory } from "../src/contracts/interfaces/IFactory.sol";

import { SafetyBits } from "../src/contracts/libraries/SafetyBits.sol";

import "../src/contracts/types/UserCallTypes.sol";
import "../src/contracts/types/LockTypes.sol";

contract MockDAppControl is DummyDAppControl {
    constructor(address escrow) DummyDAppControl(escrow) { }
}

contract ExecutionEnvironmentTest is BaseTest {
    using SafetyBits for EscrowKey;

    ExecutionEnvironment public executionEnvironment;
    MockDAppControl public dAppControl;

    EscrowKey public escrowKey;

    address public constant user = address(999);

    function setUp() public override {
        super.setUp();

        address governance = address(888);

        vm.startPrank(address(governance));
        dAppControl = new MockDAppControl(escrow);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.integrateDApp(address(dAppControl));
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
        userOp.from = address(0); // Invalid from
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
        userOp.to = address(0); // Invalid to
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
        (bool success,) = address(executionEnvironment).call(preOpsData);
        assertTrue(success);

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

        // NotDelegated
        // TODO

        // WrongDepth
        // TODO
    }
}
