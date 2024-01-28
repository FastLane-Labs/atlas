// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

contract SurchargeTest is BaseTest {
    function testSurchargeRecipient() public {
        // Check if the surcharge recipient is set to the correct address on deploy
        assertEq(atlas.surchargeRecipient(), payee, "surcharge recipient should be set to payee");
    }
}
