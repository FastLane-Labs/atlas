// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { DAppIntegration } from "../src/contracts/atlas/DAppIntegration.sol";
import { FastLaneErrorsEvents } from "../src/contracts/types/Emissions.sol";

import { DummyDAppControl } from "./base/DummyDAppControl.sol";

import "../src/contracts/types/GovernanceTypes.sol";

contract MockDAppIntegration is DAppIntegration {
    constructor(address _atlas) DAppIntegration(_atlas) { }

    function initializeNonceInternal(address account) external returns (bool) {
        return _initializeNonce(account);
    }
}

contract DAppIntegrationTest is Test {
    MockDAppIntegration public dAppIntegration;
    DummyDAppControl public dAppControl;

    address governance = makeAddr("governance");
    address signatory = makeAddr("signatory");

    function setUp() public {
        dAppIntegration = new MockDAppIntegration(address(0));
        dAppControl = new DummyDAppControl(address(0), governance);
    }

    function test_initializeGovernance() public {
        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.initializeGovernance(address(dAppControl));

        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl)));
        assertFalse(dAppIntegration.signatories(signatoryKey));

        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        assertTrue(dAppIntegration.signatories(signatoryKey));

        vm.prank(governance);
        vm.expectRevert(FastLaneErrorsEvents.OwnerActive.selector);
        dAppIntegration.initializeGovernance(address(dAppControl));
    }

    function test_addSignatory() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.addSignatory(address(dAppControl), signatory);

        bytes32 signatoryKey = keccak256(abi.encode(governance, signatory));
        assertFalse(dAppIntegration.signatories(signatoryKey));

        vm.prank(governance);
        dAppIntegration.addSignatory(address(dAppControl), signatory);

        assertTrue(dAppIntegration.signatories(signatoryKey));

        vm.prank(governance);
        vm.expectRevert(FastLaneErrorsEvents.SignatoryActive.selector);
        dAppIntegration.addSignatory(address(dAppControl), signatory);
    }

    function test_removeSignatory() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        vm.expectRevert(FastLaneErrorsEvents.InvalidCaller.selector);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);

        bytes32 signatoryKey = keccak256(abi.encode(governance, signatory));
        assertTrue(dAppIntegration.signatories(signatoryKey));

        vm.prank(governance);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);

        assertFalse(dAppIntegration.signatories(signatoryKey));

        vm.prank(governance);
        vm.expectRevert(FastLaneErrorsEvents.InvalidDAppControl.selector);
        dAppIntegration.removeSignatory(address(dAppControl), makeAddr("other"));
    }

    function test_integrateDApp() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.integrateDApp(address(dAppControl));

        bytes32 key = keccak256(abi.encode(address(dAppControl), governance, dAppControl.callConfig()));
        assertFalse(dAppIntegration.dapps(key) == address(dAppControl).codehash);

        vm.prank(governance);
        dAppIntegration.integrateDApp(address(dAppControl));

        assertTrue(dAppIntegration.dapps(key) == address(dAppControl).codehash);
    }

    function test_disableDApp() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.integrateDApp(address(dAppControl));
        vm.stopPrank();

        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.disableDApp(address(dAppControl));

        bytes32 key = keccak256(abi.encode(address(dAppControl), governance, dAppControl.callConfig()));
        assertTrue(dAppIntegration.dapps(key) == address(dAppControl).codehash);

        vm.prank(governance);
        dAppIntegration.disableDApp(address(dAppControl));

        assertFalse(dAppIntegration.dapps(key) == address(dAppControl).codehash);
    }

    function test_initializeNonce() public {
        dAppIntegration.initializeNonce(governance);

        bytes32 bitmapKey = keccak256(abi.encode(governance, 1));
        (uint128 LowestEmptyBitmap, uint128 HighestEmptyBitmap) = dAppIntegration.asyncNonceBitIndex(governance);
        (uint8 highestUsedNonce, uint240 bitmap) = dAppIntegration.asyncNonceBitmap(bitmapKey);

        assertEq(LowestEmptyBitmap, uint128(2));
        assertEq(HighestEmptyBitmap, uint128(0));

        assertEq(highestUsedNonce, uint8(1));
        assertEq(bitmap, uint240(0));
    }

    function test_initializeNonce_internal() public {
        assertTrue(dAppIntegration.initializeNonceInternal(governance));
        assertFalse(dAppIntegration.initializeNonceInternal(governance));
    }

    function test_getGovFromControl() public {
        vm.expectRevert(FastLaneErrorsEvents.DAppNotEnabled.selector);
        dAppIntegration.getGovFromControl(address(dAppControl));

        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        assertEq(dAppIntegration.getGovFromControl(address(dAppControl)), governance);
    }
}
