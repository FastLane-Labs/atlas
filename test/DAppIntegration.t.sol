// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { DAppIntegration } from "src/contracts/atlas/DAppIntegration.sol";
import { FastLaneErrorsEvents } from "src/contracts/types/Emissions.sol";

import { DummyDAppControl, CallConfigBuilder } from "./base/DummyDAppControl.sol";

import "src/contracts/types/GovernanceTypes.sol";

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
    address invalid = makeAddr("invalid");

    function setUp() public {
        dAppIntegration = new MockDAppIntegration(address(0));
        dAppControl = new DummyDAppControl(address(0), governance, CallConfigBuilder.allFalseCallConfig());
    }

    function test_initializeGovernance_successfullyInitialized() public {
        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl), governance));
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        assertTrue(
            dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be true when initialized"
        );
    }

    function test_initializeGovernance_notInitialized() public {
        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl), governance));
        assertFalse(
            dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be false when not initialized"
        );
    }

    function test_initializeGovernance_onlyGovernanceAllowed() public {
        vm.prank(invalid);
        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.initializeGovernance(address(dAppControl));
    }

    function test_initializeGovernance_alreadyInitialized() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        vm.expectRevert(FastLaneErrorsEvents.OwnerActive.selector);
        dAppIntegration.initializeGovernance(address(dAppControl));
        vm.stopPrank();
    }

    function test_addSignatory_successfullyAdded() public {
        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl), signatory));

        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        assertTrue(dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be true when added");
        vm.stopPrank();
    }

    function test_addSignatory_notSignatory() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl), signatory));
        assertFalse(
            dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be false when not added"
        );
    }

    function test_addSignatory_onlyGovernanceAllowed() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        vm.prank(invalid);
        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.addSignatory(address(dAppControl), signatory);
    }

    function test_addSignatory_alreadyActive() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.expectRevert(FastLaneErrorsEvents.SignatoryActive.selector);
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();
    }

    function test_removeSignatory_successfullyRemovedByGovernance() public {
        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl), signatory));

        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        assertFalse(
            dAppIntegration.signatories(signatoryKey),
            "signatories[signatoryKey] should be false when governance removes a signatory"
        );
    }

    function test_removeSignatory_successfullyRemovedBySignatoryItself() public {
        bytes32 signatoryKey = keccak256(abi.encode(governance, address(dAppControl), signatory));

        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        vm.prank(signatory);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);

        assertFalse(
            dAppIntegration.signatories(signatoryKey),
            "signatories[signatoryKey] should be false when a signatory removes itself"
        );
    }

    function test_removeSignatory_invalidCaller() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        vm.prank(invalid);
        vm.expectRevert(FastLaneErrorsEvents.InvalidCaller.selector);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);
    }

    function test_removeSignatory_invalidSignatoryKey() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);
        // signatoryKey is now invalid
        vm.expectRevert(FastLaneErrorsEvents.InvalidDAppControl.selector);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);
        vm.stopPrank();
    }

    function test_disableDApp_successfullyDisabled() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.disableDApp(address(dAppControl));
        vm.stopPrank();

        (address gov, uint32 callConfig, uint64 lastUpdate) = dAppIntegration.governance(address(dAppControl));

        assertTrue(gov == address(0), "gov should be address(0)");
        assertTrue(callConfig == 0, "callConfig should be 0");
        assertTrue(lastUpdate == 0, "lastUpdate should be 0");
    }

    function test_disableDApp_onlyGovernanceAllowed() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        vm.stopPrank();

        vm.prank(invalid);
        vm.expectRevert(FastLaneErrorsEvents.OnlyGovernance.selector);
        dAppIntegration.disableDApp(address(dAppControl));
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
        assertTrue(dAppIntegration.initializeNonceInternal(governance), "should return true when initialized");
        assertFalse(dAppIntegration.initializeNonceInternal(governance), "should return false when already initialized");
    }

    function test_getGovFromControl() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        assertEq(
            dAppIntegration.getGovFromControl(address(dAppControl)), governance, "should return correct governance"
        );
    }

    function test_getGovFromControl_dAppNotEnabled() public {
        vm.expectRevert(FastLaneErrorsEvents.DAppNotEnabled.selector);
        dAppIntegration.getGovFromControl(address(dAppControl));
    }
}
