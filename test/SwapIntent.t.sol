// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {BaseTest} from "./base/BaseTest.t.sol";

import {ProtocolCall} from "../src/contracts/types/CallTypes.sol";

// QUESTIONS:
// 1. What is escrowDuration (constructor arg in Atlas, Escrow.sol)? Where is it used?

// Refactor Ideas:
// 1. Lots of bitwise operations explicitly coded in contracts - could be a helper lib thats more readable


contract SwapIntentTest is BaseTest {


    function setUp() public virtual override {
        BaseTest.setUp();
    }

    function testAtlasSwapUsingIntent() public {
        // Swap 10 WETH for 20 FXS


        uint8 v;
        bytes32 r;
        bytes32 s;

        ProtocolCall memory protocolCall = helper.getProtocolCall();
        // UserCall memory userCall = helper.buildUserCall(POOL_ONE, userEOA, TOKEN_ONE);

        address executionEnvironment = atlas.createExecutionEnvironment(protocolCall);
        vm.label(address(executionEnvironment), "EXECUTION ENV");


        console.log("userEOA", userEOA);
        console.log("atlas", address(atlas));
        console.log("escrow", address(escrow));
        console.log("control", address(control));
        console.log("executionEnvironment", executionEnvironment);



    }

}