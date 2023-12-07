// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

contract AtlETHTest is BaseTest {
    function testBasicFunctionalities() public {
        // solverOne deposited 1 ETH into Atlas in BaseTest.setUp
        assertTrue(atlas.balanceOf(solverOneEOA) == 1 ether, "solverOne's atlETH balance should be 1");

        uint256 ethBalanceBefore = address(solverOneEOA).balance;
        vm.startPrank(solverOneEOA);
        // Bond 1 ETH so we can test the unbonding process
        atlas.bond(1 ether);

        // Call unbond to initiate the waiting period after which AtlETH can be burnt and ETH withdrawn
        atlas.unbond(1 ether);

        vm.stopPrank();

        uint256 activeFork = vm.activeFork();

        vm.rollFork(activeFork, block.number + atlas.ESCROW_DURATION() + 1);
        vm.selectFork(activeFork);

        vm.startPrank(solverOneEOA);

        // Handle the withdrawal.
        atlas.withdraw(1 ether);
        uint256 ethBalanceAfter = address(solverOneEOA).balance;

        assertTrue(atlas.balanceOf(solverOneEOA) == 0, "solverOne's atlETH balance should be 0");
        assertTrue(
            ethBalanceAfter == ethBalanceBefore + 1 ether, "solverOne's ETH balance should have been increased 1"
        );

        vm.stopPrank();
    }
}
