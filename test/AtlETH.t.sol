// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import {AtlasEvents} from "src/contracts/types/AtlasEvents.sol";
import {AtlasErrors} from "src/contracts/types/AtlasErrors.sol";

contract AtlETHTest is BaseTest {

    // AtlETH Tests

    function test_atleth_deposit() public {
        uint256 totalSupplyBefore = atlas.totalSupply();
        assertEq(atlas.balanceOf(userEOA), 0, "user's atlETH balance should be 0");

        deal(userEOA, 1e18);
        vm.prank(userEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Transfer(address(0), userEOA, 1e18);
        atlas.deposit{ value: 1e18 }();

        assertEq(atlas.balanceOf(userEOA), 1e18, "user's atlETH balance should be 1 ETH");
        assertEq(atlas.totalSupply(), totalSupplyBefore + 1e18, "total atlETH supply should be 1 ETH more");
    }

    function test_atleth_withdraw() public {
        uint256 totalSupplyBefore = atlas.totalSupply();
        uint256 solverEthBalanceBefore = address(solverOneEOA).balance;
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");

        vm.prank(solverOneEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Transfer(solverOneEOA, address(0), 1e18);
        atlas.withdraw(1e18);

        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.totalSupply(), totalSupplyBefore - 1e18, "total atlETH supply should be 1 ETH less");
        assertEq(address(solverOneEOA).balance, solverEthBalanceBefore + 1e18, "solverOne's ETH balance should be 1 ETH more");

        // Testing _deduct(from, amount) within withdraw
        uint256 solverTwoAtlETH = atlas.balanceOf(solverTwoEOA);
        uint256 snapshot = vm.snapshot();

        // Test withdraw less than full AtlETH balance
        vm.prank(solverTwoEOA);
        atlas.withdraw(solverTwoAtlETH / 2);

        assertEq(atlas.balanceOf(solverTwoEOA), solverTwoAtlETH / 2, "solverTwo's atlETH balance should be half of what it was");

        // Test withdraw 2x AtlETH balance - should revert with custom error
        vm.revertTo(snapshot);
        vm.startPrank(solverTwoEOA);
        atlas.bond(1e18);
        atlas.unbond(1e18);
        vm.expectRevert(abi.encodeWithSelector(AtlasErrors.InsufficientBalanceForDeduction.selector, 0, 2e18));
        atlas.withdraw(solverTwoAtlETH * 2);
        vm.stopPrank();

        // Test withdraw after unbonding and waiting the escrow duration
        vm.revertTo(snapshot);
        vm.startPrank(solverTwoEOA);
        atlas.bond(1e18);
        atlas.unbond(1e18);
        vm.stopPrank();

        assertEq(atlas.balanceOfUnbonding(solverTwoEOA), 1e18, "unbonding atleth should be 1 ETH");
        vm.roll(block.number + atlas.ESCROW_DURATION() + 1);
        assertEq(atlas.balanceOfUnbonding(solverTwoEOA), 1e18, "unbonding atleth should still be 1 ETH");
        solverEthBalanceBefore = address(solverTwoEOA).balance;

        vm.prank(solverTwoEOA);
        atlas.withdraw(solverTwoAtlETH);

        assertEq(atlas.balanceOf(solverTwoEOA), 0, "solverTwo's atlETH balance should be 0");
        assertEq(atlas.balanceOfUnbonding(solverTwoEOA), 0, "unbonding atleth should be 0");
        assertEq(address(solverTwoEOA).balance, solverEthBalanceBefore + 1e18, "solverTwo's ETH balance should be 1 ETH more");
    }

    function test_atleth_bond() public {
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOfBonded(solverOneEOA), 0, "solverOne's bonded atlETH should be 0");
        assertEq(atlas.bondedTotalSupply(), 0, "total bonded atlETH supply should be 0");

        vm.prank(solverOneEOA);
        vm.expectRevert(); // Underflow error
        atlas.bond(2e18);

        vm.prank(solverOneEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Bond(solverOneEOA, 1e18);
        atlas.bond(1e18);

        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.balanceOfBonded(solverOneEOA), 1e18, "solverOne's bonded atlETH should be 1 ETH");
        assertEq(atlas.bondedTotalSupply(), 1e18, "total bonded atlETH supply should be 1 ETH");
    }

    function test_atleth_depositAndBond() public {
        assertEq(atlas.balanceOf(userEOA), 0, "user's atlETH balance should be 0");
        assertEq(atlas.balanceOfBonded(userEOA), 0, "user's bonded atlETH should be 0");
        assertEq(atlas.bondedTotalSupply(), 0, "total bonded atlETH supply should be 0");

        deal(userEOA, 1e18);

        vm.prank(userEOA);
        vm.expectRevert(); // Underflow error
        atlas.depositAndBond{ value: 1e18 }(2e18);

        vm.prank(userEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Transfer(address(0), userEOA, 1e18);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Bond(userEOA, 1e18);
        atlas.depositAndBond{ value: 1e18 }(1e18);

        assertEq(atlas.balanceOf(userEOA), 0, "user's atlETH balance should still be 0");
        assertEq(atlas.balanceOfBonded(userEOA), 1e18, "user's bonded atlETH should be 1 ETH");
        assertEq(atlas.bondedTotalSupply(), 1e18, "total bonded atlETH supply should be 1 ETH");
    }

    function test_atleth_unbond() public {
        vm.startPrank(solverOneEOA);
        atlas.bond(1e18);

        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.balanceOfBonded(solverOneEOA), 1e18, "solverOne's bonded atlETH should be 1 ETH");
        assertEq(atlas.balanceOfUnbonding(solverOneEOA), 0, "solverOne's unbonding atlETH should be 0");
        assertEq(atlas.accountLastActiveBlock(solverOneEOA), 0, "solverOne's last active block should be 0");
        assertEq(atlas.bondedTotalSupply(), 1e18, "total bonded atlETH supply should be 1 ETH");

        // Reverts if unbonding more than bonded balance
        vm.expectRevert(); // Underflow error
        atlas.unbond(2e18);

        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Unbond(solverOneEOA, 1e18, block.number + atlas.ESCROW_DURATION() + 1);
        atlas.unbond(1e18);

        // NOTE: On unbonding, individual account bonded balances decrease, but total bonded supply remains the same
        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.balanceOfBonded(solverOneEOA), 0, "solverOne's bonded atlETH should be 1 ETH");
        assertEq(atlas.balanceOfUnbonding(solverOneEOA), 1e18, "solverOne's unbonding atlETH should be 1 ETH");
        assertEq(atlas.accountLastActiveBlock(solverOneEOA), block.number, "solverOne's last active block should be the current block");
        assertEq(atlas.bondedTotalSupply(), 1e18, "total bonded atlETH supply should be 1e18");
    }

    function test_atleth_redeem() public {
        vm.startPrank(solverOneEOA);
        atlas.bond(1e18);
        atlas.unbond(1e18);

        uint256 solverEthBefore = address(solverOneEOA).balance;
        uint256 totalSupplyBefore = atlas.totalSupply();
        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.balanceOfUnbonding(solverOneEOA), 1e18, "solverOne's unbonding atlETH should be 1 ETH");
        assertEq(atlas.bondedTotalSupply(), 1e18, "total bonded atlETH supply should be 1 ETH");

        vm.expectRevert(AtlasErrors.EscrowLockActive.selector);
        atlas.redeem(1e18);

        vm.roll(block.number + atlas.ESCROW_DURATION() + 1);

        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Redeem(solverOneEOA, 1e18);
        atlas.redeem(1e18);

        assertEq(address(solverOneEOA).balance, solverEthBefore, "solverOne's ETH balance should be the same");
        assertEq(atlas.totalSupply(), totalSupplyBefore + 1e18, "total atlETH supply should be 1 ETH more");
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOfUnbonding(solverOneEOA), 0, "solverOne's unbonding atlETH should be 0");
        assertEq(atlas.bondedTotalSupply(), 0, "total bonded atlETH supply should be 0");
    }

    // ERC20 Function Tests

    function test_atleth_approve() public {
        // solverOne deposited 1 ETH into Atlas in BaseTest.setUp
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.allowance(solverOneEOA, userEOA), 0, "solverOne's allowance for user should be 0");

        vm.prank(solverOneEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Approval(solverOneEOA, userEOA, 1e18);
        atlas.approve(userEOA, 1e18);

        assertEq(atlas.allowance(solverOneEOA, userEOA), 1e18, "solverOne's allowance for user should be 1 ETH");
    }

    function test_atleth_transfer() public {
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOf(userEOA), 0, "user's atlETH balance should be 0");

        vm.prank(solverOneEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Transfer(solverOneEOA, userEOA, 1e18);
        atlas.transfer(userEOA, 1e18);

        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.balanceOf(userEOA), 1e18, "user's atlETH balance should be 1 ETH");
    }

    function test_atleth_transferFrom() public {
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOf(solverTwoEOA), 1e18, "solverTwo's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOf(userEOA), 0, "user's atlETH balance should be 0");

        vm.prank(solverOneEOA);
        atlas.approve(userEOA, 1e18); // approve only 1 ETH

        vm.prank(userEOA);
        atlas.transferFrom(solverOneEOA, userEOA, 1e18);

        assertEq(atlas.balanceOf(solverOneEOA), 0, "solverOne's atlETH balance should be 0");
        assertEq(atlas.balanceOf(solverTwoEOA), 1e18, "solverTwo's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOf(userEOA), 1e18, "user's atlETH balance should be 1 ETH");


        vm.prank(solverTwoEOA);
        atlas.approve(userEOA, type(uint256).max); // approve max
        
        vm.prank(userEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Transfer(solverTwoEOA, userEOA, 1e18);
        atlas.transferFrom(solverTwoEOA, userEOA, 1e18);

        assertEq(atlas.balanceOf(solverTwoEOA), 0, "solverTwo's atlETH balance should be 0");
        assertEq(atlas.balanceOf(userEOA), 2e18, "user's atlETH balance should be 2 ETH");
    }

    function test_atleth_permit() public {
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.allowance(solverOneEOA, userEOA), 0, "solverOne's allowance for user should be 0");

        bytes32 domainSeparator = atlas.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        solverOneEOA,
                        userEOA,
                        1e18,
                        atlas.nonces(solverOneEOA),
                        type(uint256).max
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(solverOnePK, digest);

        vm.prank(userEOA);
        vm.expectEmit(true, true, false, true);
        emit AtlasEvents.Approval(solverOneEOA, userEOA, 1e18);
        atlas.permit(solverOneEOA, userEOA, 1e18, type(uint256).max, v, r, s);

        assertEq(atlas.allowance(solverOneEOA, userEOA), 1e18, "solverOne's allowance for user should be 1 ETH");
    }

    // View Function Tests
    
    function test_atleth_balanceOf() public {
        assertEq(atlas.balanceOf(solverOneEOA), 1e18, "solverOne's atlETH balance should be 1 ETH");
        assertEq(atlas.balanceOf(userEOA), 0, "user's atlETH balance should be 0");

        deal(userEOA, 1e18);
        vm.prank(userEOA);
        atlas.deposit{ value: 1e18 }();

        assertEq(atlas.balanceOf(userEOA), 1e18, "user's atlETH balance should now be 1 ETH");
    }

    function test_atleth_balanceOfBonded() public {
        assertEq(atlas.balanceOfBonded(solverOneEOA), 0, "solverOne's bonded atlETH starts at 0");
        assertEq(atlas.bondedTotalSupply(), 0, "total bonded atlETH supply should be 0");

        vm.prank(solverOneEOA);
        atlas.bond(1e18);

        assertEq(atlas.balanceOfBonded(solverOneEOA), 1e18, "solverOne's bonded atlETH should be 1 ETH");
        assertEq(atlas.bondedTotalSupply(), 1e18, "total bonded atlETH supply should be 1 ETH");
    }

    function test_atleth_balanceOfUnbonding() public {
        assertEq(atlas.balanceOfUnbonding(solverOneEOA), 0, "solverOne's unbonding atlETH starts at 0");

        vm.startPrank(solverOneEOA);
        atlas.bond(1e18);
        atlas.unbond(1e18);
        vm.stopPrank();

        assertEq(atlas.balanceOfUnbonding(solverOneEOA), 1e18, "solverOne's unbonding atlETH should be 1 ETH"); 
    }

    function test_atleth_accountLastActiveBlock() public {
        assertEq(atlas.accountLastActiveBlock(solverOneEOA), 0, "solverOne's last active block should be 0");

        vm.startPrank(solverOneEOA);
        atlas.bond(1e18);
        atlas.unbond(1e18);
        vm.stopPrank();

        assertEq(atlas.accountLastActiveBlock(solverOneEOA), block.number, "solverOne's last active block should be the current block");
    }

    function test_atleth_unbondingCompleteBlock() public {
        assertEq(atlas.unbondingCompleteBlock(solverOneEOA), 0, "solverOne's unbonding complete block should be 0");

        vm.startPrank(solverOneEOA);
        atlas.bond(1e18);
        atlas.unbond(1e18);
        vm.stopPrank();

        assertEq(atlas.unbondingCompleteBlock(solverOneEOA), block.number + atlas.ESCROW_DURATION(), "solverOne's unbonding complete block should be the current block + 64");
    }

    function test_atleth_domainSeparator() public {
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("Atlas ETH"),
                    keccak256("1"),
                    block.chainid,
                    address(atlas)
                )
        );
        assertEq(atlas.DOMAIN_SEPARATOR(), expectedDomainSeparator, "domainSeparator should be expected value");

        // Change chainId to check _computeDomainSeparator() is run
        vm.chainId(321);

        assertTrue(atlas.DOMAIN_SEPARATOR() != expectedDomainSeparator, "domainSeparator should change with chainId");
    }
}
