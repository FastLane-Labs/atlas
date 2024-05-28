// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { ExecutionEnvironment } from "src/contracts/atlas/ExecutionEnvironment.sol";
import { DAppIntegration } from "src/contracts/atlas/DAppIntegration.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import { DummyDAppControl, CallConfigBuilder } from "./base/DummyDAppControl.sol";

contract MockDAppIntegration is DAppIntegration {
    constructor(address _atlas) DAppIntegration(_atlas) { }
}

contract DAppIntegrationTest is Test {
    Atlas public atlas;
    MockDAppIntegration public dAppIntegration;
    DummyDAppControl public dAppControl;

    address atlasDeployer = makeAddr("atlas deployer");
    address governance = makeAddr("governance");
    address signatory = makeAddr("signatory");
    address invalid = makeAddr("invalid");

    function setUp() public {
    
        vm.startPrank(atlasDeployer);
        // Computes the addresses at which AtlasVerification will be deployed
        address expectedAtlasAddr = vm.computeCreateAddress(atlasDeployer, vm.getNonce(atlasDeployer) + 1);
        address expectedAtlasVerificationAddr = vm.computeCreateAddress(atlasDeployer, vm.getNonce(atlasDeployer) + 2);
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedAtlasAddr, "AtlasFactory 1.0"));
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedAtlasAddr);

        atlas = new Atlas({
            _escrowDuration: 64,
            _verification: expectedAtlasVerificationAddr,
            _simulator: address(0),
            _executionTemplate: address(execEnvTemplate),
            _surchargeRecipient: atlasDeployer
        });
        dAppIntegration = new MockDAppIntegration(expectedAtlasAddr);
        vm.stopPrank();

        dAppControl = new DummyDAppControl(expectedAtlasAddr, governance, CallConfigBuilder.allFalseCallConfig());
    }

    function test_initializeGovernance_successfullyInitialized() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), governance));
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        assertTrue(
            dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be true when initialized"
        );
    }

    function test_initializeGovernance_notInitialized() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), governance));
        assertFalse(
            dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be false when not initialized"
        );
    }

    function test_initializeGovernance_onlyGovernanceAllowed() public {
        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.OnlyGovernance.selector);
        dAppIntegration.initializeGovernance(address(dAppControl));
    }

    function test_initializeGovernance_alreadyInitialized() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        vm.expectRevert(AtlasErrors.SignatoryActive.selector);
        dAppIntegration.initializeGovernance(address(dAppControl));
        vm.stopPrank();
    }

    function test_addSignatory_successfullyAdded() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));

        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        assertTrue(dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be true when added");
        vm.stopPrank();
    }

    function test_addSignatory_notSignatory() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));
        assertFalse(
            dAppIntegration.signatories(signatoryKey), "signatories[signatoryKey] should be false when not added"
        );
    }

    function test_addSignatory_onlyGovernanceAllowed() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.OnlyGovernance.selector);
        dAppIntegration.addSignatory(address(dAppControl), signatory);
    }

    function test_addSignatory_alreadyActive() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.expectRevert(AtlasErrors.SignatoryActive.selector);
        dAppIntegration.addSignatory(address(dAppControl), signatory);
        vm.stopPrank();
    }

    function test_removeSignatory_successfullyRemovedByGovernance() public {
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));

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
        bytes32 signatoryKey = keccak256(abi.encodePacked(address(dAppControl), signatory));

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
        vm.expectRevert(AtlasErrors.InvalidCaller.selector);
        dAppIntegration.removeSignatory(address(dAppControl), signatory);
    }

    function test_disableDApp_successfullyDisabled() public {
        assertEq(dAppIntegration.isDAppSignatory(address(dAppControl), governance), false);

        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        assertEq(dAppIntegration.isDAppSignatory(address(dAppControl), governance), true);
        dAppIntegration.disableDApp(address(dAppControl));
        vm.stopPrank();

        assertEq(dAppIntegration.isDAppSignatory(address(dAppControl), governance), false);
    }

    function test_disableDApp_onlyGovernanceAllowed() public {
        vm.startPrank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        vm.stopPrank();

        vm.prank(invalid);
        vm.expectRevert(AtlasErrors.OnlyGovernance.selector);
        dAppIntegration.disableDApp(address(dAppControl));
    }

    function test_getGovFromControl() public {
        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));
        assertEq(
            dAppIntegration.getGovFromControl(address(dAppControl)), governance, "should return correct governance"
        );
    }

    function test_getGovFromControl_dAppNotEnabled() public {
        vm.expectRevert(AtlasErrors.DAppNotEnabled.selector);
        dAppIntegration.getGovFromControl(address(dAppControl));
    }

    function test_getDAppSignatories() public {
        assertEq(new address[](0), dAppIntegration.getDAppSignatories(address(dAppControl)), "should start as empty array");

        vm.prank(governance);
        dAppIntegration.initializeGovernance(address(dAppControl));

        address[] memory signatories = dAppIntegration.getDAppSignatories(address(dAppControl));
        assertEq(signatories.length, 1, "should return 1 signatory");
        assertEq(signatories[0], governance, "gov should be a signatory");

        vm.prank(governance);
        dAppIntegration.addSignatory(address(dAppControl), signatory);

        signatories = dAppIntegration.getDAppSignatories(address(dAppControl));
        assertEq(signatories.length, 2, "should return 2 signatories");
        assertEq(signatories[1], signatory, "should return correct 2nd signatory");

        address anotherSignatory = makeAddr("anotherSignatory");
        vm.prank(governance);
        dAppIntegration.addSignatory(address(dAppControl), anotherSignatory);

        signatories = dAppIntegration.getDAppSignatories(address(dAppControl));
        assertEq(signatories.length, 3, "should return 3 signatories");
        assertEq(signatories[2], anotherSignatory, "should return correct 3rd signatory");
    }
}
