// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../src/contracts/libraries/AccountingMath.sol";

contract AccountingMathTest is Test {
    function testWithBundlerSurcharge() public {
        assertEq(AccountingMath.withBundlerSurcharge(0), uint256(0));
        assertEq(AccountingMath.withBundlerSurcharge(1), uint256(1));
        assertEq(AccountingMath.withBundlerSurcharge(11), uint256(12));
        assertEq(AccountingMath.withBundlerSurcharge(100), uint256(110));
        assertEq(AccountingMath.withBundlerSurcharge(1e18), uint256(11e17));
        vm.expectRevert();
        AccountingMath.withBundlerSurcharge(type(uint256).max);
    }

    function testWithoutBundlerSurcharge() public {
        assertEq(AccountingMath.withoutBundlerSurcharge(0), uint256(0));
        assertEq(AccountingMath.withoutBundlerSurcharge(1), uint256(0));
        assertEq(AccountingMath.withoutBundlerSurcharge(12), uint256(10));
        assertEq(AccountingMath.withoutBundlerSurcharge(110), uint256(100));
        assertEq(AccountingMath.withoutBundlerSurcharge(11e17), uint256(1e18));
        vm.expectRevert();
        AccountingMath.withoutBundlerSurcharge(type(uint256).max);
    }

    function testWithAtlasAndBundlerSurcharges() public {
        assertEq(AccountingMath.withAtlasAndBundlerSurcharges(0), uint256(0));
        assertEq(AccountingMath.withAtlasAndBundlerSurcharges(1), uint256(1));
        assertEq(AccountingMath.withAtlasAndBundlerSurcharges(10), uint256(12));
        assertEq(AccountingMath.withAtlasAndBundlerSurcharges(100), uint256(120));
        assertEq(AccountingMath.withAtlasAndBundlerSurcharges(1e18), uint256(12e17));
        vm.expectRevert();
        AccountingMath.withAtlasAndBundlerSurcharges(type(uint256).max);
    }

    function testGetAtlasSurcharge() public {
        assertEq(AccountingMath.getAtlasSurcharge(0), uint256(0));
        assertEq(AccountingMath.getAtlasSurcharge(10), uint256(1));
        assertEq(AccountingMath.getAtlasSurcharge(20), uint256(2));
        assertEq(AccountingMath.getAtlasSurcharge(30), uint256(3));
        assertEq(AccountingMath.getAtlasSurcharge(100), uint256(10));
        assertEq(AccountingMath.getAtlasSurcharge(1_000_000), uint256(100_000));
        assertEq(AccountingMath.getAtlasSurcharge(1e18), uint256(1e17));
        vm.expectRevert();
        AccountingMath.getAtlasSurcharge(type(uint256).max);
    }

    function testSolverGasLimitScaledDown() public {
        assertEq(AccountingMath.solverGasLimitScaledDown(0, 100), uint256(0));
        assertEq(AccountingMath.solverGasLimitScaledDown(50, 100), uint256(47)); // 50 * 10_000_000 / 10_500_000
        assertEq(AccountingMath.solverGasLimitScaledDown(100, 200), uint256(95));
        
        assertEq(AccountingMath.solverGasLimitScaledDown(200, 100), uint256(95));
        assertEq(AccountingMath.solverGasLimitScaledDown(300, 200), uint256(190));
        
        assertEq(AccountingMath.solverGasLimitScaledDown(100, 100), uint256(95));
        assertEq(AccountingMath.solverGasLimitScaledDown(200, 200), uint256(190));
        
        assertEq(AccountingMath.solverGasLimitScaledDown(1_000_000, 500_000), uint256(476_190)); // 500_000 * 10_000_000 / 10_500_000
        assertEq(AccountingMath.solverGasLimitScaledDown(1e18, 1e18), uint256(952380952380952380));
        
        vm.expectRevert();
        assertEq(AccountingMath.solverGasLimitScaledDown(type(uint256).max, type(uint256).max), type(uint256).max);
        
        assertEq(AccountingMath.solverGasLimitScaledDown(1, 2), uint256(0)); // 1 * 10_000_000 / 10_500_000
        assertEq(AccountingMath.solverGasLimitScaledDown(3, 3), uint256(2)); // 3 * 10_000_000 / 10_500_000
        assertEq(AccountingMath.solverGasLimitScaledDown(5, 10), uint256(4)); // 5 * 10_000_000 / 10_500_000

    }
}
