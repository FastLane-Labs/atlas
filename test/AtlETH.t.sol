// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

contract AtlETHTest is BaseTest {

    // AtlETH Tests

    function test_atleth_bond() public {}

    // View Function Tests
    
    function test_atleth_balanceOf() public {

    }

    function test_atleth_balanceOfBonded() public {

    }

    function test_atleth_balanceOfUnbonding() public {

    }

    function test_atleth_accountLastActiveBlock() public {

    }

    function test_atleth_unbondingCompleteBlock() public {

    }

    // ERC20 Function Tests

    // TODO


    function testBasicFunctionalities() public {
        // solverOne deposited 1 ETH into Atlas in BaseTest.setUp
        assertTrue(atlas.balanceOf(solverOneEOA) == 1 ether, "solverOne's atlETH balance should be 1");
        assertEq(atlas.totalSupply(), 2 ether, "total atlETH supply should be 2");

        uint256 ethBalanceBefore = address(solverOneEOA).balance;
        vm.startPrank(solverOneEOA);

        // Bond 1 ETH so we can test the unbonding process
        atlas.bond(1 ether);

        // Call unbond to initiate the waiting period after which AtlETH can be burnt and ETH withdrawn
        atlas.unbond(1 ether);

        vm.stopPrank();

        uint256 activeFork = vm.activeFork();

        vm.rollFork(activeFork, block.number + atlas.ESCROW_DURATION() + 2);
        vm.selectFork(activeFork);

        vm.startPrank(solverOneEOA);

        // Handle the withdrawal.
        atlas.withdraw(1 ether);
        uint256 ethBalanceAfter = address(solverOneEOA).balance;

        assertTrue(atlas.balanceOf(solverOneEOA) == 0, "solverOne's atlETH balance should be 0");
        assertTrue(
            ethBalanceAfter == ethBalanceBefore + 1 ether, "solverOne's ETH balance should have been increased 1"
        );
        assertEq(atlas.totalSupply(), 1 ether, "total atlETH supply should have decreased to 1");

        vm.stopPrank();
    }

    function testWithdrawWithoutBonding() public {
        // solverOne deposited 1 ETH into Atlas in BaseTest.setUp
        assertTrue(atlas.balanceOf(solverOneEOA) == 1 ether, "solverOne's atlETH balance should be 1");
        assertEq(atlas.totalSupply(), 2 ether, "total atlETH supply should be 2");

        uint256 ethBalanceBefore = address(solverOneEOA).balance;
        vm.startPrank(solverOneEOA);

        // Call withdraw without bonding first
        atlas.withdraw(1 ether);
        uint256 ethBalanceAfter = address(solverOneEOA).balance;

        assertTrue(atlas.balanceOf(solverOneEOA) == 0, "solverOne's atlETH balance should be 0");
        assertTrue(
            ethBalanceAfter == ethBalanceBefore + 1 ether, "solverOne's ETH balance should have been increased 1"
        );
        assertEq(atlas.totalSupply(), 1 ether, "total atlETH supply should have decreased to 1");
        vm.stopPrank();
    }
}
