// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { IDAppIntegration } from "src/contracts/interfaces/IDAppIntegration.sol";
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";

import { V2ExPost } from "src/contracts/examples/ex-post-mev-example/V2ExPost.sol";

import { SolverExPost } from "src/contracts/solver/src/TestSolverExPost.sol";

import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/DAppApprovalTypes.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { V2Helper } from "./V2Helper.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";

import "forge-std/Test.sol";

contract ExPostTest is BaseTest {

    V2ExPost public v2ExPost;
    /// forge-config: default.gas_price = 15000000000

    function setUp() public virtual override {
        BaseTest.setUp();

        // Deposit ETH from Searcher1 signer to pay for searcher's gas
        vm.prank(solverOneEOA);
        atlas.deposit{ value: 1e18 }();

        // Deposit ETH from Searcher2 signer to pay for searcher's gas
        vm.prank(solverTwoEOA);
        atlas.deposit{ value: 1e18 }();

        v2ExPost = new V2ExPost(address(atlas));
    }

    function test_ExPostMEV() public {

        uint8 v;
        bytes32 r;
        bytes32 s;

        UserOperation memory userOp = helper.buildUserOperation(POOL_ONE, POOL_TWO, userEOA, TOKEN_ONE);
        userOp.control = address(v2ExPost);

        // user does not sign their own operation when bundling
        // (v, r, s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        // userOp.signature = abi.encodePacked(r, s, v);

        SolverOperation[] memory solverOps = new SolverOperation[](2);
        bytes memory solverOpData;

        console.log("solverOneEOA WETH:", WETH.balanceOf(address(solverOneEOA)));
        console.log("solverOneXP  WETH:", WETH.balanceOf(address(solverOneXP)));

        vm.prank(address(solverOneEOA));
        atlas.bond(1 ether);

        vm.prank(address(solverTwoEOA));
        atlas.bond(1 ether);

        // First SolverOperation
        solverOpData = helper.buildV2SolverOperationData(POOL_TWO, POOL_ONE);
        solverOps[1] = helper.buildSolverOperation(
            userOp, solverOpData, solverOneEOA, address(solverOneXP), 0, 0
        );

        (v, r, s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOps[1]));
        solverOps[1].signature = abi.encodePacked(r, s, v);

        console.log("solverTwoEOA WETH:", WETH.balanceOf(address(solverTwoEOA)));
        console.log("solverTwoXP  WETH:", WETH.balanceOf(address(solverTwoXP)));
        // Second SolverOperation
        solverOpData = helper.buildV2SolverOperationData(POOL_ONE, POOL_TWO);
        solverOps[0] = helper.buildSolverOperation(
            userOp, solverOpData, solverTwoEOA, address(solverTwoXP), 0, 0
        );

        (v, r, s) = vm.sign(solverTwoPK, atlasVerification.getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(r, s, v);

        console.log("topBid before sorting", solverOps[0].bidAmount);

        solverOps = sorter.sortBids(userOp, solverOps);

        console.log("topBid after sorting ", solverOps[0].bidAmount);

        // DAppOperation call
        DAppOperation memory dAppOp = helper.buildDAppOperation(governanceEOA, userOp, solverOps);

        (v, r, s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));

        dAppOp.signature = abi.encodePacked(r, s, v);

        vm.startPrank(userEOA);

        address executionEnvironment = atlas.createExecutionEnvironment(userOp.control);
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        console.log("userEOA", userEOA);
        console.log("atlas", address(atlas));
        console.log("control", address(control));
        console.log("executionEnvironment", executionEnvironment);

        // User must approve Atlas
        ERC20(TOKEN_ZERO).approve(address(atlas), type(uint256).max);
        ERC20(TOKEN_ONE).approve(address(atlas), type(uint256).max);

        vm.stopPrank();

        // address bundler = userEOA;
        vm.startPrank(userEOA);

        uint256 userEOABalance = userEOA.balance;
        uint256 userAtlEthBalance = atlas.balanceOf(userEOA);

        // uint256 bundlerEOABalance = bundler.balance;
        // uint256 bundlerAtlEthBalance = atlas.balanceOf(bundler);

        uint256 solverOneEOABalance = solverOneEOA.balance;
        uint256 solverOneAtlEthBalance = atlas.balanceOf(solverOneEOA);

        uint256 solverTwoEOABalance = solverTwoEOA.balance;
        uint256 solverTwoAtlEthBalance = atlas.balanceOf(solverTwoEOA);

        vm.expectEmit(true, true, true, true);
        emit AtlasEvents.MetacallResult(userEOA, userEOA, solverOps[0].from);
        emit AtlasEvents.SolverExecution(solverOps[0].from, 0, true);
        (bool success,) =
            address(atlas).call(abi.encodeWithSelector(atlas.metacall.selector, userOp, solverOps, dAppOp));

        if (success) {
            console.log("success!");
        } else {
            console.log("failure");
        }

        assertTrue(success);

        vm.stopPrank();

        /*
        console.log("--");
        console.log("BUNDLER:");

        uint256 newBundlerBalance = bundler.balance + atlas.balanceOf(bundler);
        uint256 bundlerTotalBalance = bundlerEOABalance + bundlerAtlEthBalance;

        if (bundler.balance >= bundlerEOABalance) {
            console.log("bundler eoa balance delta: +", bundler.balance - bundlerEOABalance);
        } else {
            console.log("bundler eoa balance delta: -", bundlerEOABalance - bundler.balance);
        }

        if (atlas.balanceOf(bundler) >= bundlerAtlEthBalance) {
            console.log("bundler atlETH balance delta: +", atlas.balanceOf(bundler) - bundlerAtlEthBalance);
        } else {
            console.log("bundler atlETH balance delta: -", bundlerAtlEthBalance - atlas.balanceOf(bundler));
        }

        if (newBundlerBalance >= bundlerTotalBalance) {
            console.log("combined bundler balance delta: +", newBundlerBalance - bundlerTotalBalance);
        } else {
            console.log("combined balance delta: -", bundlerTotalBalance - newBundlerBalance);
        }
        */

        console.log("--");
        console.log("USER:");

        uint256 newUserBalance = userEOA.balance + atlas.balanceOf(userEOA);
        uint256 userTotalBalance = userEOABalance + userAtlEthBalance;

        if (userEOA.balance >= userEOABalance) {
            console.log("user eoa balance delta   : +", userEOA.balance - userEOABalance);
        } else {
            console.log("user eoa balance delta   : -", userEOABalance - userEOA.balance);
        }

        if (atlas.balanceOf(userEOA) >= userAtlEthBalance) {
            console.log("user atlETH balance delta: +", atlas.balanceOf(userEOA) - userAtlEthBalance);
        } else {
            console.log("user atlETH balance delta: -", userAtlEthBalance - atlas.balanceOf(userEOA));
        }

        if (newUserBalance >= userTotalBalance) {
            console.log("user total balance delta : +", newUserBalance - userTotalBalance);
        } else {
            console.log("user total balance delta : -", userTotalBalance - newUserBalance);
        }

        console.log("--");
        console.log("SOLVER ONE:");

        uint256 newSolverOneBalance = solverOneEOA.balance + atlas.balanceOf(solverOneEOA);
        uint256 solverOneTotalBalance = solverOneEOABalance + solverOneAtlEthBalance;

        if (solverOneEOA.balance >= solverOneEOABalance) {
            console.log("solverOne eoa balance delta   : +", solverOneEOA.balance - solverOneEOABalance);
        } else {
            console.log("solverOne eoa balance delta   : -", solverOneEOABalance - solverOneEOA.balance);
        }

        if (atlas.balanceOf(solverOneEOA) >= solverOneAtlEthBalance) {
            console.log("solverOne atlETH balance delta: +", atlas.balanceOf(solverOneEOA) - solverOneAtlEthBalance);
        } else {
            console.log("solverOne atlETH balance delta: -", solverOneAtlEthBalance - atlas.balanceOf(solverOneEOA));
        }

        if (newSolverOneBalance >= solverOneTotalBalance) {
            console.log("solverOne total balance delta : +", newSolverOneBalance - solverOneTotalBalance);
        } else {
            console.log("solverOne total balance delta : -", solverOneTotalBalance - newSolverOneBalance);
        }

        console.log("--");
        console.log("SOLVER TWO:");

        uint256 newSolverTwoBalance = solverTwoEOA.balance + atlas.balanceOf(solverTwoEOA);
        uint256 solverTwoTotalBalance = solverTwoEOABalance + solverTwoAtlEthBalance;

        if (solverTwoEOA.balance >= solverTwoEOABalance) {
            console.log("solverTwo eoa balance delta   : +", solverTwoEOA.balance - solverTwoEOABalance);
        } else {
            console.log("solverTwo eoa balance delta   : -", solverTwoEOABalance - solverTwoEOA.balance);
        }

        if (atlas.balanceOf(solverTwoEOA) >= solverTwoAtlEthBalance) {
            console.log("solverTwo atlETH balance delta: +", atlas.balanceOf(solverTwoEOA) - solverTwoAtlEthBalance);
        } else {
            console.log("solverTwo atlETH balance delta: -", solverTwoAtlEthBalance - atlas.balanceOf(solverTwoEOA));
        }

        if (newSolverTwoBalance >= solverTwoTotalBalance) {
            console.log("solverTwo total balance delta : +", newSolverTwoBalance - solverTwoTotalBalance);
        } else {
            console.log("solverTwo total balance delta : -", solverTwoTotalBalance - newSolverTwoBalance);
        }
    }
}