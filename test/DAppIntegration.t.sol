// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { FactoryLib } from "../src/contracts/atlas/FactoryLib.sol";
import { Atlas } from "../src/contracts/atlas/Atlas.sol";
import { ExecutionEnvironment } from "../src/contracts/common/ExecutionEnvironment.sol";
import { DAppIntegration } from "../src/contracts/atlas/DAppIntegration.sol";
import { AtlasErrors } from "../src/contracts/types/AtlasErrors.sol";
import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

import { DummyDAppControl, CallConfigBuilder } from "./base/DummyDAppControl.sol";

contract DAppIntegrationTest is BaseTest {
    DummyDAppControl public dAppControl;

    address atlasDeployer = makeAddr("atlas deployer");
    address governance = makeAddr("governance");
    address signatory = makeAddr("signatory");
    address invalid = makeAddr("invalid");

    function setUp() public override {
        super.setUp();

        // Deploy the DummyDAppControl contract
        dAppControl = new DummyDAppControl(address(atlas), governance, CallConfigBuilder.allFalseCallConfig());
    }

    function test_initializeGovernance_successfullyInitialized() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), governance));
        vm.prank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        assertTrue(
            atlasVerification.signatories(signatoryKey), "signatories[signatoryKey] should be true when initialized"
        );
    }

    function test_initializeGovernance_notInitialized() public view {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), governance));
        assertFalse(
            atlasVerification.signatories(signatoryKey), "signatories[signatoryKey] should be false when not initialized"
        );
    }

    function test_initializeGovernance_onlyGovernanceAllowed() public {
        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.OnlyGovernance.selector);
        atlasVerification.initializeGovernance(address(dAppControl));
    }

    function test_initializeGovernance_alreadyInitialized() public {
        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        vm.expectRevert(AtlasErrors.SignatoryActive.selector);
        atlasVerification.initializeGovernance(address(dAppControl));
        vm.stopPrank();
    }

    function test_addSignatory_successfullyAdded() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));

        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.addSignatory(address(dAppControl), signatory);
        assertTrue(atlasVerification.signatories(signatoryKey), "signatories[signatoryKey] should be true when added");
        vm.stopPrank();
    }

    function test_addSignatory_notSignatory() public {
        vm.prank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));

        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));
        assertFalse(
            atlasVerification.signatories(signatoryKey), "signatories[signatoryKey] should be false when not added"
        );
    }

    function test_addSignatory_onlyGovernanceAllowed() public {
        vm.prank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));

        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.OnlyGovernance.selector);
        atlasVerification.addSignatory(address(dAppControl), signatory);
    }

    function test_addSignatory_alreadyActive() public {
        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.addSignatory(address(dAppControl), signatory);
        vm.expectRevert(AtlasErrors.SignatoryActive.selector);
        atlasVerification.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();
    }

    function test_removeSignatory_successfullyRemovedByGovernance() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));

        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.addSignatory(address(dAppControl), signatory);
        atlasVerification.removeSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        assertFalse(
            atlasVerification.signatories(signatoryKey),
            "signatories[signatoryKey] should be false when governance removes a signatory"
        );
    }

    function test_removeSignatory_successfullyRemovedBySignatoryItself() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));

        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        vm.prank(signatory);
        atlasVerification.removeSignatory(address(dAppControl), signatory);

        assertFalse(
            atlasVerification.signatories(signatoryKey),
            "signatories[signatoryKey] should be false when a signatory removes itself"
        );
    }

    function test_removeSignatory_invalidCaller() public {
        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();

        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.InvalidCaller.selector);
        atlasVerification.removeSignatory(address(dAppControl), signatory);
    }

    function test_removeSignatory_doesNotBlockGovTransferOnDAppControl() public {
        address newGov = makeAddr("newGov");

        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        vm.stopPrank();

        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), true);
        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), newGov), false);
        assertEq(dAppControl.governance(), governance);
        assertEq(dAppControl.pendingGovernance(), address(0));

        vm.startPrank(governance);
        // Gov first removes themselves as signatory on DAppIntegration
        atlasVerification.removeSignatory(address(dAppControl), governance);

        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), false, "gov should not be a signatory on DAppIntegration");
        assertEq(dAppControl.governance(), governance, "gov should still be governance on DAppControl");

        // Gov then attempts to transfer governance on DAppControl to newGov
        dAppControl.transferGovernance(newGov);
        vm.stopPrank();

        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), false, "Gov should still not be a signatory on DAppIntegration");
        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), newGov), false, "newGov should not yet be a signatory on DAppIntegration");
        assertEq(dAppControl.governance(), governance, "gov should still be governance on DAppControl");
        assertEq(dAppControl.pendingGovernance(), newGov, "newGov should be pending governance on DAppControl");

        // NewGov accepts governance on DAppControl
        vm.prank(newGov);
        dAppControl.acceptGovernance();

        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), false, "Gov should still not be a signatory on DAppIntegration");
        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), newGov), true, "newGov should now be a signatory on DAppIntegration");
        assertEq(dAppControl.governance(), newGov, "newGov should now be governance on DAppControl");
        assertEq(dAppControl.pendingGovernance(), address(0), "pending governance should be cleared on DAppControl");
    }

    function test_disableDApp_successfullyDisabled() public {
        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), false);

        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), true);
        atlasVerification.disableDApp(address(dAppControl));
        vm.stopPrank();

        assertEq(atlasVerification.isDAppSignatory(address(dAppControl), governance), false);
    }

    function test_disableDApp_onlyGovernanceAllowed() public {
        vm.startPrank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        vm.stopPrank();

        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.OnlyGovernance.selector);
        atlasVerification.disableDApp(address(dAppControl));
    }

    function test_getGovFromControl() public {
        vm.prank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));
        assertEq(
            atlasVerification.getGovFromControl(address(dAppControl)), governance, "should return correct governance"
        );
    }

    function test_getGovFromControl_dAppNotEnabled() public {
        vm.expectRevert(AtlasErrors.DAppNotEnabled.selector);
        atlasVerification.getGovFromControl(address(dAppControl));
    }

    function test_dAppSignatories() public {
        assertEq(new address[](0), atlasVerification.dAppSignatories(address(dAppControl)), "should start as empty array");

        vm.prank(governance);
        atlasVerification.initializeGovernance(address(dAppControl));

        address[] memory signatories = atlasVerification.dAppSignatories(address(dAppControl));
        assertEq(signatories.length, 1, "should return 1 signatory");
        assertEq(signatories[0], governance, "gov should be a signatory");

        vm.prank(governance);
        atlasVerification.addSignatory(address(dAppControl), signatory);

        signatories = atlasVerification.dAppSignatories(address(dAppControl));
        assertEq(signatories.length, 2, "should return 2 signatories");
        assertEq(signatories[1], signatory, "should return correct 2nd signatory");

        address anotherSignatory = makeAddr("anotherSignatory");
        vm.prank(governance);
        atlasVerification.addSignatory(address(dAppControl), anotherSignatory);

        signatories = atlasVerification.dAppSignatories(address(dAppControl));
        assertEq(signatories.length, 3, "should return 3 signatories");
        assertEq(signatories[2], anotherSignatory, "should return correct 3rd signatory");
    }
}
