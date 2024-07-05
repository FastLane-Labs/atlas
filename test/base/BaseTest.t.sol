// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

// import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { TestAtlas } from "./TestAtlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { ExecutionEnvironment } from "src/contracts/common/ExecutionEnvironment.sol";

import { Sorter } from "src/contracts/helpers/Sorter.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";

import { Solver } from "src/contracts/solver/src/TestSolver.sol";

import { V2ExPost } from "src/contracts/examples/ex-post-mev-example/V2ExPost.sol";

import { SolverExPost } from "src/contracts/solver/src/TestSolverExPost.sol";

import { V2DAppControl } from "src/contracts/examples/v2-example/V2DAppControl.sol";

import { TestConstants } from "./TestConstants.sol";

import { V2Helper } from "../V2Helper.sol";

import { Utilities } from "src/contracts/helpers/Utilities.sol";

contract BaseTest is Test, TestConstants {
    address public me = address(this);

    address public payee; // = makeAddr("FastLanePayee");

    uint256 public governancePK = 11_111;
    address public governanceEOA = vm.addr(governancePK);

    uint256 public solverOnePK = 22_222;
    address public solverOneEOA = vm.addr(solverOnePK);

    uint256 public solverTwoPK = 33_333;
    address public solverTwoEOA = vm.addr(solverTwoPK);

    uint256 public userPK = 44_444;
    address public userEOA = vm.addr(userPK);

    TestAtlas public atlas;
    AtlasVerification public atlasVerification;

    Simulator public simulator;
    Sorter public sorter;

    Solver public solverOne;
    Solver public solverTwo;

    SolverExPost public solverOneXP;
    SolverExPost public solverTwoXP;

    V2DAppControl public v2DAppControl;

    V2Helper public helper;

    Utilities public u;

    // Fork stuff
    ChainVars public chain = mainnet;
    uint256 public forkNetwork;

    function setUp() public virtual {
        forkNetwork = vm.createFork(vm.envString(chain.rpcUrlKey));
        vm.selectFork(forkNetwork);
        vm.rollFork(forkNetwork, chain.forkBlock);

        // Deal to user
        deal(TOKEN_ZERO, address(userEOA), 10e30);
        deal(TOKEN_ONE, address(userEOA), 10e30);

        // Deploy contracts
        vm.startPrank(payee);

        simulator = new Simulator();

        // Computes the addresses at which AtlasVerification will be deployed
        address expectedAtlasAddr = vm.computeCreateAddress(payee, vm.getNonce(payee) + 1);
        address expectedAtlasVerificationAddr = vm.computeCreateAddress(payee, vm.getNonce(payee) + 2);
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedAtlasAddr, "AtlasFactory 1.0"));
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedAtlasAddr);

        atlas = new TestAtlas({
            escrowDuration: 64,
            verification: expectedAtlasVerificationAddr,
            simulator: address(simulator),
            executionTemplate: address(execEnvTemplate),
            initialSurchargeRecipient: payee
        });
        atlasVerification = new AtlasVerification(address(atlas));
        simulator.setAtlas(address(atlas));
        sorter = new Sorter(address(atlas));

        vm.stopPrank();
        vm.startPrank(governanceEOA);

        v2DAppControl = new V2DAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(v2DAppControl));

        vm.stopPrank();

        vm.deal(solverOneEOA, 100e18);

        vm.startPrank(solverOneEOA);

        // Salt to avoid clashes caused by vm.rollFork() in other tests
        solverOne = new Solver{ salt: keccak256("1") }(WETH_ADDRESS, address(atlas), solverOneEOA);
        solverOneXP = new SolverExPost{ salt: keccak256("2") }(WETH_ADDRESS, address(atlas), solverOneEOA, 60);
        atlas.deposit{ value: 1e18 }();

        vm.stopPrank();

        deal(TOKEN_ZERO, address(solverOne), 10e24);
        deal(TOKEN_ONE, address(solverOne), 10e24);

        deal(TOKEN_ZERO, address(solverOneXP), 10e24);
        deal(TOKEN_ONE, address(solverOneXP), 10e24);

        vm.deal(solverTwoEOA, 100e18);

        vm.startPrank(solverTwoEOA);

        solverTwo = new Solver(WETH_ADDRESS, address(atlas), solverTwoEOA);
        solverTwoXP = new SolverExPost(WETH_ADDRESS, address(atlas), solverTwoEOA, 80);
        atlas.deposit{ value: 1e18 }();

        vm.stopPrank();

        deal(TOKEN_ZERO, address(solverTwo), 10e24);
        deal(TOKEN_ONE, address(solverTwo), 10e24);

        deal(TOKEN_ZERO, address(solverTwoXP), 10e24);
        deal(TOKEN_ONE, address(solverTwoXP), 10e24);

        helper = new V2Helper(address(v2DAppControl), address(atlas), address(atlasVerification));
        u = new Utilities();

        deal(TOKEN_ZERO, address(atlas), 1);
        deal(TOKEN_ONE, address(atlas), 1);

        vm.label(userEOA, "USER");
        vm.label(address(atlas), "ATLAS");
        vm.label(address(v2DAppControl), "V2 DAPP CONTROL");
    }
}
