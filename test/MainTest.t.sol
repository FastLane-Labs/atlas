// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {IEscrow} from "../src/contracts/interfaces/IEscrow.sol";
import {IAtlas} from "../src/contracts/interfaces/IAtlas.sol";
import {IDAppIntegration} from "../src/contracts/interfaces/IDAppIntegration.sol";

import {Atlas} from "../src/contracts/atlas/Atlas.sol";
import {Mimic} from "../src/contracts/atlas/Mimic.sol";

import {V2DAppControl} from "../src/contracts/examples/v2-example/V2DAppControl.sol";

import {Solver} from "src/contracts/solver/src/TestSolver.sol";

import "../src/contracts/types/UserCallTypes.sol";
import "../src/contracts/types/SolverCallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/DAppApprovalTypes.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {V2Helper} from "./V2Helper.sol";
import {DAppOperationSigner} from "./DAppOperationSigner.sol";

import "forge-std/Test.sol";

contract MainTest is BaseTest {
    /// forge-config: default.gas_price = 15000000000
    function setUp() public virtual override {
        BaseTest.setUp();

        // Deposit ETH from Searcher1 signer to pay for searcher's gas 
        vm.prank(solverOneEOA); 
        atlas.deposit{value: 1e18}(solverOneEOA);

        // Deposit ETH from Searcher2 signer to pay for searcher's gas
        vm.prank(solverTwoEOA);
        atlas.deposit{value: 1e18}(solverTwoEOA);
    }

    function testMain() public {
        uint8 v;
        bytes32 r;
        bytes32 s;

        DAppConfig memory dConfig = helper.getDAppConfig();

        UserOperation memory userOp = helper.buildUserOperation(POOL_ONE, userEOA, TOKEN_ONE);

        (v, r, s) = vm.sign(userPK, IAtlas(address(atlas)).getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(r, s, v);

        SolverOperation[] memory solverOps = new SolverOperation[](2);
        bytes memory solverOpData;
        // First SolverOperation
        solverOpData = helper.buildV2SolverOperationData(POOL_TWO, POOL_ONE);
        solverOps[1] =
            helper.buildSolverOperation(userOp, dConfig, solverOpData, solverOneEOA, address(solverOne), 2e17);

        (v, r, s) = vm.sign(solverOnePK, IAtlas(address(atlas)).getSolverPayload(solverOps[1]));
        solverOps[1].signature = abi.encodePacked(r, s, v);
        
        // Second SolverOperation
        solverOpData = helper.buildV2SolverOperationData(POOL_ONE, POOL_TWO);
        solverOps[0] =
            helper.buildSolverOperation(userOp, dConfig, solverOpData, solverTwoEOA, address(solverTwo), 1e17);

        (v, r, s) = vm.sign(solverTwoPK, IAtlas(address(atlas)).getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(r, s, v);

        console.log("topBid before sorting",solverOps[0].bids[0].bidAmount);
        
        solverOps = sorter.sortBids(userOp, solverOps);

        console.log("topBid after sorting ",solverOps[0].bids[0].bidAmount);

        // DAppOperation call
        DAppOperation memory dAppOp =
            helper.buildDAppOperation(governanceEOA, dConfig, userOp, solverOps);

        (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getDAppOperationPayload(dAppOp));

        dAppOp.signature = abi.encodePacked(r, s, v);

        vm.startPrank(userEOA);

        address executionEnvironment = IAtlas(address(atlas)).createExecutionEnvironment(dConfig);
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        console.log("userEOA", userEOA);
        console.log("atlas", address(atlas));
        console.log("control", address(control));
        console.log("executionEnvironment", executionEnvironment);

        // User must approve Atlas
        ERC20(TOKEN_ZERO).approve(address(atlas), type(uint256).max);
        ERC20(TOKEN_ONE).approve(address(atlas), type(uint256).max);

        uint256 userBalance = userEOA.balance;

        (bool success,) = address(atlas).call(
            abi.encodeWithSelector(
                atlas.metacall.selector, dConfig, userOp, solverOps, dAppOp
            )
        );

        assertTrue(success);
        console.log("user gas refund received",userEOA.balance - userBalance);
        console.log("user refund equivalent gas usage", (userEOA.balance - userBalance)/tx.gasprice);
        
        vm.stopPrank();

        /*
        console.log("");
        console.log("-");
        console.log("-");

        // Second attempt
        dConfig = helper.getDAppConfig();

        userOp = helper.buildUserOperation(POOL_ONE, userEOA, TOKEN_ONE);

        // First SolverOperation
        solverOps[0] =
            helper.buildSolverOperation(userOp, dConfig, solverOneEOA, address(solverOne), POOL_ONE, POOL_TWO, 2e17);

        (v, r, s) = vm.sign(solverOnePK, IAtlas(address(atlas)).getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(r, s, v);

        // Second SolverOperation
        solverOps[1] =
            helper.buildSolverOperation(userOp, dConfig, solverTwoEOA, address(solverTwo), POOL_TWO, POOL_ONE, 1e17);

        (v, r, s) = vm.sign(solverTwoPK, IAtlas(address(atlas)).getSolverPayload(solverOps[1]));
        solverOps[1].signature = abi.encodePacked(r, s, v);

        // DAppOperation call
        dAppOp =
            helper.buildDAppOperation(governanceEOA, dConfig, userOp, solverOps);

        (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getDAppOperationPayload(dAppOp));

        dAppOp.signature = abi.encodePacked(r, s, v);

        vm.startPrank(userEOA);

        executionEnvironment = IAtlas(address(atlas)).getExecutionEnvironment(userOp.from, address(control));
        
        userBalance = userEOA.balance;

        (success,) = address(atlas).call(
            abi.encodeWithSelector(
                atlas.metacall.selector, dConfig, userOp, solverOps, dAppOp
            )
        );

        assertTrue(success);
        console.log("user gas refund received",userEOA.balance - userBalance);
        console.log("user refund equivalent gas usage", (userEOA.balance - userBalance)/tx.gasprice);

        vm.stopPrank();
        */
    }

    /*
    function testMimic() public {
        address aaaaa = address(this);
        address bbbbb = msg.sender;
        address ccccc = address(this);
        uint16 ddddd = uint16(0x1111);
        bytes32 eeeee = keccak256(abi.encodePacked(uint256(0x2222)));
        // Mimic mimic = new Mimic();
        //console.log("----");
        //console.log("runtime code:");
        //console.logBytes(address(mimic).code);
        console.log("aaaaa", aaaaa);
        console.log("bbbbb", bbbbb);
        console.log("ccccc", ccccc);
        console.logBytes32(eeeee);
        console.log("----");
        console.log("creation code:");
        console.logBytes(type(Mimic).creationCode);
        console.log("----");

        bytes memory creationCode = type(Mimic).creationCode;
        //bytes memory creationCode = new bytes(790);
        assembly {
            mstore(add(creationCode, 85), add(
                shl(96, aaaaa), 
                0x73ffffffffffffffffffffff
            ))
            mstore(add(creationCode, 131), add(
                shl(96, bbbbb), 
                0x73ffffffffffffffffffffff
            ))
            mstore(add(creationCode, 152), add(
                shl(96, ccccc), 
                add(
                    add(
                        shl(88, 0x61), 
                        shl(72, ddddd)
                    ),
                    0x7f0000000000000000
                )
            ))
            mstore(add(creationCode, 176), eeeee)
        }
        
        console.log("assembly modified code:");
        console.logBytes(creationCode);
        console.log("----");
    }
    */

    function testTestUserOperation() public {
        uint8 v;
        bytes32 r;
        bytes32 s;

        DAppConfig memory dConfig = helper.getDAppConfig();
        UserOperation memory userOp = helper.buildUserOperation(POOL_ONE, userEOA, TOKEN_ONE);
        (v, r, s) = vm.sign(userPK, IAtlas(address(atlas)).getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(r, s, v);

        vm.startPrank(userEOA);
        IAtlas(address(atlas)).createExecutionEnvironment(dConfig);

        // Failure case, user hasn't approved Atlas for TOKEN_ONE, operation must fail
        assertFalse(simulator.simUserOperation(userOp), "UserOperation tested true");

        // Success case
        ERC20(TOKEN_ONE).approve(address(atlas), type(uint256).max);
        assertTrue(simulator.simUserOperation(userOp), "UserOperation tested false");

        vm.stopPrank();
    }

    function testSolverCalls() public {
        uint8 v;
        bytes32 r;
        bytes32 s;

        DAppConfig memory dConfig = helper.getDAppConfig();
        UserOperation memory userOp = helper.buildUserOperation(POOL_ONE, userEOA, TOKEN_ONE);
        (v, r, s) = vm.sign(userPK, IAtlas(address(atlas)).getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(r, s, v);

        SolverOperation[] memory solverOps = new SolverOperation[](1);

        // Success case
        bytes memory solverOpData = helper.buildV2SolverOperationData(POOL_TWO, POOL_ONE);
        solverOps[0] = helper.buildSolverOperation(
            userOp, dConfig, solverOpData, solverOneEOA, address(solverOne), 2e17
        );
        (v, r, s) = vm.sign(solverOnePK, IAtlas(address(atlas)).getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(r, s, v);
        DAppOperation memory dAppOp =
            helper.buildDAppOperation(governanceEOA, dConfig, userOp, solverOps);
        (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(r, s, v);
        vm.startPrank(userEOA);
        IAtlas(address(atlas)).createExecutionEnvironment(dConfig);
        ERC20(TOKEN_ONE).approve(address(atlas), type(uint256).max);
        (bool success, bytes memory data) = address(simulator).call(
            abi.encodeWithSelector(
                simulator.simSolverCalls.selector, userOp, solverOps, dAppOp
            )
        );

        assertTrue(success, "Success case tx reverted unexpectedly");
        assertTrue(abi.decode(data, (bool)), "Success case tx did not return true");
        vm.stopPrank();

        // Failure case
        solverOpData = helper.buildV2SolverOperationData(POOL_TWO, POOL_TWO); // this will make the solver operation revert
        solverOps[0] = helper.buildSolverOperation(
            userOp, dConfig, solverOpData, solverOneEOA, address(solverOne), 2e17
        );
        (v, r, s) = vm.sign(solverOnePK, IAtlas(address(atlas)).getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(r, s, v);
        dAppOp = helper.buildDAppOperation(governanceEOA, dConfig, userOp, solverOps);
        (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(r, s, v);
        vm.startPrank(userEOA);
        (success, data) = address(simulator).call(
            abi.encodeWithSelector(
                simulator.simSolverCalls.selector, userOp, solverOps, dAppOp
            )
        );

        assertTrue(success, "Failure case tx reverted unexpectedly");
        assertFalse(abi.decode(data, (bool)), "Failure case did not return false");
        vm.stopPrank();
    }
}
