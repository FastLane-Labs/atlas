// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { FastLaneErrorsEvents, AtlasEvents } from "src/contracts/types/Emissions.sol";

contract SurchargeTest is BaseTest {
    function testSurchargeRecipient() public {
        // Check if the surcharge recipient is set to the correct address on deploy
        assertEq(atlas.surchargeRecipient(), payee, "surcharge recipient should be set to payee");
    
        // Check a random cant transfer the surcharge recipient
        vm.expectRevert(FastLaneErrorsEvents.InvalidAccess.selector);
        atlas.newSurchargeRecipient(address(this));

        // Check the transfer process works as expected
        vm.startPrank(atlas.surchargeRecipient());
        vm.expectEmit(true, true, true, true);
        emit AtlasEvents.SurchargeRecipientTransferStarted(payee, address(this));
        atlas.newSurchargeRecipient(address(this));
        assertEq(atlas.surchargeRecipient(), payee, "recipient should not change until accepted by new address");

        // Check that only correct recipient can accept the transfer
        vm.expectRevert(FastLaneErrorsEvents.InvalidAccess.selector);
        atlas.becomeSurchargeRecipient();
        vm.stopPrank();

        // Check transfer acceptance works
        vm.expectEmit(true, true, true, true);
        emit AtlasEvents.SurchargeRecipientTransferred(address(this));
        atlas.becomeSurchargeRecipient();
        assertEq(atlas.surchargeRecipient(), address(this), "recipient should change to new address");
    }
}
