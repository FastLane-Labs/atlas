// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { BoAtlETH } from "src/contracts/atlas/BoAtlETH.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

contract AtlETHTest is BaseTest {
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

    function testBondedAtlETHBalances() public {
        // Deploy new Atlas contract with 0 escrow duration for this test
        vm.startPrank(payee);
        address expectedBoAtlEthAddr = computeCreateAddress(payee, vm.getNonce(payee) + 1);
        atlas = new Atlas({
            _escrowDuration: 0,
            _factory: address(0),
            _verification: address(0),
            _boAtlETH: expectedBoAtlEthAddr,
            _simulator: address(0)
        });
        boAthETH = new BoAtlETH(address(atlas));
        vm.stopPrank();

        BoAtlETH boAtlETH = BoAtlETH(atlas.BOATLETH());

        vm.prank(solverOneEOA);
        atlas.deposit{ value: 1 ether }();

        // solverOne's atlETH balance should be 1
        assertTrue(atlas.balanceOf(solverOneEOA) == 1 ether, "solverOne's atlETH balance should be 1");

        // solverOne hasn't bonded yet
        assertTrue(boAtlETH.balanceOf(solverOneEOA) == 0, "solverOne's boAtlETH balance should be 0");

        // solverOne bonds 1 ETH
        vm.prank(solverOneEOA);
        atlas.bond(1 ether);

        // solverOne's atlETH balance should be 0
        assertTrue(atlas.balanceOf(solverOneEOA) == 0, "solverOne's atlETH balance should be 0");

        // solverOne's boAtlETH balance should be 1
        assertTrue(boAtlETH.balanceOf(solverOneEOA) == 1 ether, "solverOne's boAtlETH balance should be 1");

        uint256 ethBalanceBefore = address(solverOneEOA).balance;

        // solverOne unbonds and withdraws 1 ETH
        vm.startPrank(solverOneEOA);
        atlas.unbond(1 ether);
        atlas.withdraw(1 ether);
        vm.stopPrank();

        // solverOne's atlETH balance should be 0
        assertTrue(atlas.balanceOf(solverOneEOA) == 0, "solverOne's atlETH balance should be 0");

        // solverOne's boAtlETH balance should be 0
        assertTrue(boAtlETH.balanceOf(solverOneEOA) == 0, "solverOne's boAtlETH balance should be 0");

        uint256 ethBalanceAfter = address(solverOneEOA).balance;

        // solverOne's ETH balance should have increased by 1
        assertTrue(
            ethBalanceAfter == ethBalanceBefore + 1 ether, "solverOne's ETH balance should have been increased 1"
        );
    }
}
