// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";
import { BaseTest } from "./base/BaseTest.t.sol";
import { ArbitrageTest } from "./base/ArbitrageTest.t.sol";
import { SolverBase } from "../src/contracts/solver/SolverBase.sol";

contract FlashLoanTest is BaseTest {
    Sig public sig;
    ArbitrageTest public arb;

    function setUp() public virtual override {
        BaseTest.setUp();

        arb = new ArbitrageTest();
        arb.setUpArbitragePools(chain.weth, chain.dai, 50e18, 100_000e18, address(v2Router), address(s2Router));
    }

    function testFlashLoanArbitrage() public {

    } 

}

contract SimpleArbitrageSolver is SolverBase {
}