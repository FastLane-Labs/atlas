// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import {AtlasEvents} from "src/contracts/types/AtlasEvents.sol";

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
    }

    function test_atleth_bond() public {}

    function test_atleth_depositAndBond() public {}

    function test_atleth_unbond() public {}

    function test_atleth_redeem() public {}

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
        bytes32 domainSeparator = atlas.DOMAIN_SEPARATOR();
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("Atlas ETH"),
                    keccak256("1"),
                    block.chainid,
                    address(atlas)
                )
        );
        assertEq(domainSeparator, expectedDomainSeparator, "domainSeparator not as expected");
    }

    // TODO - OLD tests - move to above

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
