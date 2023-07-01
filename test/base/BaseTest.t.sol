// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {IEscrow} from "../../src/contracts/interfaces/IEscrow.sol";
import {IProtocolIntegration} from "../../src/contracts/interfaces/IProtocolIntegration.sol";

import {Atlas} from "../../src/contracts/atlas/Atlas.sol";

import {Searcher} from "../searcher/src/TestSearcher.sol";

import {V2ProtocolControl} from "../../src/contracts/v2-example/V2ProtocolControl.sol";

import {TestConstants} from "./TestConstants.sol";

import {Helper} from "../Helpers.sol";

contract BaseTest is Test, TestConstants {
    address public me = address(this);
    
    address public payee = makeAddr("FastLanePayee"); 

    address public governanceEOA = makeAddr("ProtocolGovernanceEOA"); 
    uint256 public governancePK = 1111;

    address public searcherOneEOA = makeAddr("SearcherEOA1");
    uint256 public searcherOnePK = 2222;

    address public searcherTwoEOA = makeAddr("SearcherEOA2");
    uint256 public searcherTwoPK = 3333;

    address public userEOA = makeAddr("UserEOA");

    Atlas public atlas;
    address public escrow;

    Searcher public searcherOne;
    Searcher public searcherTwo;

    V2ProtocolControl public control;

    Helper public helper;

    // Fork stuff
    ChainVars public chain = MAINNET;
    uint256 public forkNetwork;

    function setUp() public virtual {
        forkNetwork = vm.createFork(vm.envString(chain.RPC_URL_KEY));
        vm.selectFork(forkNetwork);
        vm.rollFork(forkNetwork, chain.FORK_BLOCK);

        // Deploy contracts
        vm.startPrank(payee);

        atlas = new Atlas(payee, 64);
        escrow = atlas.getEscrowAddress();

        vm.stopPrank();
        vm.startPrank(governanceEOA);

        control = new V2ProtocolControl(escrow);
        atlas.initializeGovernance(address(control));
        atlas.integrateProtocol(address(control), V2_FXS_ETH);
        atlas.integrateProtocol(address(control), S2_FXS_ETH);

        vm.stopPrank();

        vm.deal(searcherOneEOA, 100E18);

        vm.startPrank(searcherOneEOA);

        searcherOne = new Searcher(escrow, searcherOneEOA);
        IEscrow(escrow).deposit{value: 1E18}(searcherOneEOA);

        vm.stopPrank();

        vm.deal(searcherTwoEOA, 100E18);
        
        vm.startPrank(searcherTwoEOA);

        searcherTwo = new Searcher(escrow, searcherTwoEOA);
        IEscrow(escrow).deposit{value: 1E18}(searcherTwoEOA);

        vm.stopPrank();

        helper = new Helper(address(control), escrow, address(atlas));
    }
}