// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IDAppIntegration } from "src/contracts/interfaces/IDAppIntegration.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasFactory } from "src/contracts/atlas/AtlasFactory.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { GasAccountingLib } from "src/contracts/atlas/GasAccountingLib.sol";
import { SafetyLocksLib } from "src/contracts/atlas/SafetyLocksLib.sol";

import { Sorter } from "src/contracts/helpers/Sorter.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";

import { Solver } from "src/contracts/solver/src/TestSolver.sol";

import { V2DAppControl } from "src/contracts/examples/v2-example/V2DAppControl.sol";

import { TestConstants } from "./TestConstants.sol";

import { V2Helper } from "../V2Helper.sol";

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

    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    GasAccountingLib public gasAccountingLib;
    SafetyLocksLib public safetyLocksLib;

    Simulator public simulator;
    Sorter public sorter;

    address public escrow;

    Solver public solverOne;
    Solver public solverTwo;

    V2DAppControl public control;

    V2Helper public helper;

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

        // Computes the addresses at which AtlasFactory and AtlasVerification will be deployed
        address expectedAtlasFactoryAddr = computeCreateAddress(payee, vm.getNonce(payee) + 1);
        address expectedAtlasVerificationAddr = computeCreateAddress(payee, vm.getNonce(payee) + 2);
        address expectedGasAccountingLibAddr = computeCreateAddress(payee, vm.getNonce(payee) + 3);
        address expectedSafetyLocksLibAddr = computeCreateAddress(payee, vm.getNonce(payee) + 4);

        atlas = new Atlas({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator)
        });
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));
        gasAccountingLib = new GasAccountingLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });
        safetyLocksLib = new SafetyLocksLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });

        simulator.setAtlas(address(atlas));

        escrow = address(atlas);
        sorter = new Sorter(address(atlas), escrow);

        vm.stopPrank();
        vm.startPrank(governanceEOA);

        control = new V2DAppControl(escrow);
        atlasVerification.initializeGovernance(address(control));
        atlasVerification.integrateDApp(address(control));

        vm.stopPrank();

        vm.deal(solverOneEOA, 100e18);

        vm.startPrank(solverOneEOA);

        solverOne = new Solver(escrow, solverOneEOA);
        atlas.deposit{ value: 1e18 }();

        deal(TOKEN_ZERO, address(solverOne), 10e24);
        deal(TOKEN_ONE, address(solverOne), 10e24);

        vm.deal(solverTwoEOA, 100e18);

        vm.startPrank(solverTwoEOA);

        solverTwo = new Solver(escrow, solverTwoEOA);
        atlas.deposit{ value: 1e18 }();

        vm.stopPrank();

        deal(TOKEN_ZERO, address(solverTwo), 10e24);
        deal(TOKEN_ONE, address(solverTwo), 10e24);

        helper = new V2Helper(address(control), address(atlas), address(atlasVerification));

        deal(TOKEN_ZERO, address(atlas), 1);
        deal(TOKEN_ONE, address(atlas), 1);

        vm.label(userEOA, "USER");
        vm.label(escrow, "ESCROW");
        vm.label(address(atlas), "ATLAS");
        vm.label(address(control), "DAPP CONTROL");
    }
}
