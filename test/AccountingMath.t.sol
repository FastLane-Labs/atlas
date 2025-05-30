// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/libraries/AccountingMath.sol";

contract AccountingMathTest is Test {
    uint256 DEFAULT_ATLAS_SURCHARGE_RATE = 1_000; // 10%
    uint256 DEFAULT_BUNDLER_SURCHARGE_RATE = 1_000; // 10%

    /// forge-config: default.allow_internal_expect_revert = true
    function testWithBundlerSurcharge() public {
        assertEq(AccountingMath.withSurcharge(0, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(0));
        assertEq(AccountingMath.withSurcharge(1, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(1));
        assertEq(AccountingMath.withSurcharge(11, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(12));
        assertEq(AccountingMath.withSurcharge(100, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(110));
        assertEq(AccountingMath.withSurcharge(1e18, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(11e17));
        vm.expectRevert();
        AccountingMath.withSurcharge(type(uint256).max, DEFAULT_BUNDLER_SURCHARGE_RATE);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testWithoutBundlerSurcharge() public {
        assertEq(AccountingMath.withoutSurcharge(0, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(0));
        assertEq(AccountingMath.withoutSurcharge(1, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(0));
        assertEq(AccountingMath.withoutSurcharge(12, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(10));
        assertEq(AccountingMath.withoutSurcharge(110, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(100));
        assertEq(AccountingMath.withoutSurcharge(11e17, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(1e18));
        vm.expectRevert();
        AccountingMath.withoutSurcharge(type(uint256).max, DEFAULT_BUNDLER_SURCHARGE_RATE);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testWithAtlasAndBundlerSurcharges() public {
        assertEq(
            AccountingMath.withSurcharges(0, DEFAULT_ATLAS_SURCHARGE_RATE, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(0)
        );
        assertEq(
            AccountingMath.withSurcharges(1, DEFAULT_ATLAS_SURCHARGE_RATE, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(1)
        );
        assertEq(
            AccountingMath.withSurcharges(10, DEFAULT_ATLAS_SURCHARGE_RATE, DEFAULT_BUNDLER_SURCHARGE_RATE), uint256(12)
        );
        assertEq(
            AccountingMath.withSurcharges(100, DEFAULT_ATLAS_SURCHARGE_RATE, DEFAULT_BUNDLER_SURCHARGE_RATE),
            uint256(120)
        );
        assertEq(
            AccountingMath.withSurcharges(1e18, DEFAULT_ATLAS_SURCHARGE_RATE, DEFAULT_BUNDLER_SURCHARGE_RATE),
            uint256(12e17)
        );
        vm.expectRevert();
        AccountingMath.withSurcharges(type(uint256).max, DEFAULT_ATLAS_SURCHARGE_RATE, DEFAULT_BUNDLER_SURCHARGE_RATE);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testGetAtlasSurcharge() public {
        assertEq(AccountingMath.getSurcharge(0, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(0));
        assertEq(AccountingMath.getSurcharge(10, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(1));
        assertEq(AccountingMath.getSurcharge(20, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(2));
        assertEq(AccountingMath.getSurcharge(30, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(3));
        assertEq(AccountingMath.getSurcharge(100, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(10));
        assertEq(AccountingMath.getSurcharge(1_000_000, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(100_000));
        assertEq(AccountingMath.getSurcharge(1e18, DEFAULT_ATLAS_SURCHARGE_RATE), uint256(1e17));
        vm.expectRevert();
        AccountingMath.getSurcharge(type(uint256).max, DEFAULT_ATLAS_SURCHARGE_RATE);
    }
}
