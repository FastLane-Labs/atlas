// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {BaseTest} from "./base/BaseTest.t.sol";

// QUESTIONS:
// 1. What is escrowDuration (constructor arg in Atlas, Escrow.sol)? Where is it used?


contract SwapIntentTest is BaseTest {


    function setUp() public virtual override {
        BaseTest.setUp();
    }

    function testAtlasSwapUsingIntent() public {

        // Swap 10 WETH for 20 FXS


    }

}