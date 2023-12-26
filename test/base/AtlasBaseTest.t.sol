// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IDAppIntegration } from "src/contracts/interfaces/IDAppIntegration.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { ExecutionEnvironment } from "src/contracts/atlas/ExecutionEnvironment.sol";

import { Sorter } from "src/contracts/helpers/Sorter.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";

import { Solver } from "src/contracts/solver/src/TestSolver.sol";

import { V2DAppControl } from "src/contracts/examples/v2-example/V2DAppControl.sol";

import { TestConstants } from "./TestConstants.sol";

import { V2Helper } from "../V2Helper.sol";

import { Utilities } from "src/contracts/helpers/Utilities.sol";

contract AtlasBaseTest is Test, TestConstants {
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

    Atlas public atlas;
    AtlasVerification public atlasVerification;

    Simulator public simulator;
    Sorter public sorter;

    address public escrow;

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
        address expectedAtlasAddr = computeCreateAddress(payee, vm.getNonce(payee) + 1);
        address expectedAtlasVerificationAddr = computeCreateAddress(payee, vm.getNonce(payee) + 1);
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedAtlasAddr, "AtlasFactory 1.0"));
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedAtlasAddr);

        atlas = new Atlas({
            _escrowDuration: 64,
            _verification: expectedAtlasVerificationAddr,
            _simulator: address(simulator),
            _executionTemplate: address(execEnvTemplate)
        });
        atlasVerification = new AtlasVerification(address(atlas));

        simulator.setAtlas(address(atlas));

        escrow = address(atlas);
        sorter = new Sorter(address(atlas), escrow);

        vm.stopPrank();

        vm.label(userEOA, "USER");
        vm.label(escrow, "ESCROW");
        vm.label(address(atlas), "ATLAS");
    }
}
