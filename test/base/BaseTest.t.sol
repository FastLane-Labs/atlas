// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {IEscrow} from "../../src/contracts/interfaces/IEscrow.sol";
import {IProtocolIntegration} from "../../src/contracts/interfaces/IProtocolIntegration.sol";

import {Atlas} from "../../src/contracts/atlas/Atlas.sol";
import {Sorter} from "../../src/contracts/atlas/Sorter.sol";

import {Searcher} from "../searcher/src/TestSearcher.sol";

import {V2ProtocolControl} from "../../src/contracts/v2-example/V2ProtocolControl.sol";

import {TestConstants} from "./TestConstants.sol";

import {V2Helper} from "../V2Helper.sol";

contract BaseTest is Test, TestConstants {
    address public me = address(this);

    address public payee = makeAddr("FastLanePayee");

    uint256 public governancePK = 11111;
    address public governanceEOA = vm.addr(governancePK);

    uint256 public searcherOnePK = 22222;
    address public searcherOneEOA = vm.addr(searcherOnePK);

    uint256 public searcherTwoPK = 33333;
    address public searcherTwoEOA = vm.addr(searcherTwoPK);

    uint256 public userPK = 44444;
    address public userEOA = vm.addr(userPK);

    Atlas public atlas;
    address public escrow;

    Sorter public sorter;

    Searcher public searcherOne;
    Searcher public searcherTwo;

    V2ProtocolControl public control;

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

        atlas = new Atlas(64);
        escrow = atlas.getEscrowAddress();
        sorter = new Sorter(address(atlas), escrow);

        vm.stopPrank();
        vm.startPrank(governanceEOA);

        control = new V2ProtocolControl(escrow);
        atlas.initializeGovernance(address(control));
        atlas.integrateProtocol(address(control), V2_FXS_ETH);
        atlas.integrateProtocol(address(control), S2_FXS_ETH);

        vm.stopPrank();

        vm.deal(searcherOneEOA, 100e18);

        vm.startPrank(searcherOneEOA);

        searcherOne = new Searcher(escrow, searcherOneEOA);
        // IEscrow(escrow).deposit{value: 1e18}(searcherOneEOA);

        vm.stopPrank();

        deal(TOKEN_ZERO, address(searcherOne), 10e24);
        deal(TOKEN_ONE, address(searcherOne), 10e24);

        vm.deal(searcherTwoEOA, 100e18);

        vm.startPrank(searcherTwoEOA);

        searcherTwo = new Searcher(escrow, searcherTwoEOA);
        IEscrow(escrow).deposit{value: 1e18}(searcherTwoEOA);

        vm.stopPrank();

        deal(TOKEN_ZERO, address(searcherTwo), 10e24);
        deal(TOKEN_ONE, address(searcherTwo), 10e24);

        helper = new V2Helper(address(control), escrow, address(atlas));

        deal(TOKEN_ZERO, address(atlas), 1);
        deal(TOKEN_ONE, address(atlas), 1);

        vm.label(userEOA, "USER");
        vm.label(escrow, "ESCROW");
        vm.label(address(atlas), "ATLAS");
        vm.label(address(control), "PROTOCOL CONTROL");
    }
}
