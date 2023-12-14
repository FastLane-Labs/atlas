// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

import { ExecutionEnvironment } from "../src/contracts/atlas/ExecutionEnvironment.sol";
import { DAppControl } from "../src/contracts/dapp/DAppControl.sol";

import { IFactory } from "../src/contracts/interfaces/IFactory.sol";

import { SafetyBits } from "../src/contracts/libraries/SafetyBits.sol";

import "../src/contracts/types/DAppApprovalTypes.sol";
import "../src/contracts/types/UserCallTypes.sol";
import "../src/contracts/types/SolverCallTypes.sol";
import "../src/contracts/types/LockTypes.sol";

contract ExecutionEnvironmentTest is BaseTest {
    using SafetyBits for EscrowKey;

    ExecutionEnvironment public executionEnvironment;
    MockDAppControl public dAppControl;

    EscrowKey public escrowKey;

    address public constant governance = address(888);
    address public constant user = address(999);

    CallConfig private callConfig;

    function setupDAppControl(CallConfig memory customCallConfig) internal {
        vm.startPrank(governance);
        dAppControl = new MockDAppControl(escrow, governance, customCallConfig);
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

        setupDAppControl(callConfig);

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

        setupDAppControl(callConfig);

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

        // NotDelegated
        // TODO

        // WrongDepth
        // TODO
    }

    function test_modifier_validControlHash() public {
        UserOperation memory userOp;
        bytes memory userData;
        bool status;

        setupDAppControl(callConfig);

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
        // TODO
    }

    function test_modifier_contributeSurplus() public {
        // TODO ?
    }

    function test_preOpsWrapper() public {
        UserOperation memory userOp;
        bytes memory preOpsData;
        bool status;
        bytes memory data;

        setupDAppControl(callConfig);

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

        setupDAppControl(callConfig);

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

    function _allocateValueCall(address, uint256, bytes calldata) internal virtual override { }
    function getBidFormat(UserOperation calldata) public view virtual override returns (address) { }
    function getBidValue(SolverOperation calldata) public view virtual override returns (uint256) { }

    /*//////////////////////////////////////////////////////////////
                            CUSTOM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mockOperation(bool shouldRevert, uint256 returnValue) public pure returns (uint256) {
        require(!shouldRevert, "revert requested");
        return returnValue;
    }
}
