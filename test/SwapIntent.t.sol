// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {ProtocolCall, UserCall, SearcherCall} from "../src/contracts/types/CallTypes.sol";
import {Verification} from "../src/contracts/types/VerificationTypes.sol";

// QUESTIONS:
// 1. What is escrowDuration (constructor arg in Atlas, Escrow.sol)? Where is it used?
// 2. Is the Atlas contract always also the Escrow contract? Would Escrow ever be separate?
// 3. What is staging call and staging lock? How does it work?
//      A: Checks protocolCall config for requireStaging, then calls holdStagingLock() on EscrowKey
// 4. What is userSelector (bytes4) in _stagingCall?

// Refactor Ideas:
// 1. Lots of bitwise operations explicitly coded in contracts - could be a helper lib thats more readable
// 2. helper is currently a V2Helper and shared from BaseTest. Should only be in Uni V2 related tests
// 3. Need a more generic helper for BaseTest

// Doc Ideas:
// 1. Step by step instructions for building a metacall transaction (for internal testing, and integrating protocols)


contract SwapIntentTest is BaseTest {

    TxBuilder public txBuilder;

    function setUp() public virtual override {
        BaseTest.setUp();

        txBuilder = new TxBuilder({
            protocolControl: address(control),
            escrowAddress: address(escrow),
            atlasAddress: address(atlas)
        });
    }

    function testAtlasSwapUsingIntent() public {
        // Swap 10 WETH for 20 FXS

        // Input params for Atlas.metacall() - will be populated below
        ProtocolCall memory protocolCall;
        UserCall memory userCall;
        SearcherCall[] memory searcherCalls = new SearcherCall[](1); 
        SearcherCall memory searcherCall; // First and only searcher will succeed
        Verification memory verification; 


        // uint8 v;
        // bytes32 r;
        // bytes32 s;

        protocolCall = txBuilder.getProtocolCall();

        // userCallData is used in delegatecall from exec env to control, calling stagingCall
        // first 4 bytes are "userSelector" param in stagingCall in ProtocolControl
        // rest of data is "userData" param
        bytes memory userCallData = ""; // TODO finish

        // Builds the metaTx and to parts of userCall, signature still to be set
        userCall = txBuilder.buildUserCall({
            from: userEOA, // NOTE: Would from ever not be user?
            to: address(atlas),
            maxFeePerGas: 0, // TODO update
            value: 0,
            data: userCallData
        });

        // Builds the SearcherCall
        searcherCall = txBuilder.buildSearcherCall({
            userCall: userCall,
            protocolCall: protocolCall,
            searcherCallData: "", // TODO update
            searcherEOA: searcherOneEOA,
            searcherContract: address(searcherOne),
            bidAmount: 1e18
        });

        searcherCalls[0] = searcherCall;


        // Frontend creates verification after seeing rest of data
        // verification;


        address executionEnvironment = atlas.createExecutionEnvironment(protocolCall);
        vm.label(address(executionEnvironment), "EXECUTION ENV");


        console.log("userEOA", userEOA);
        console.log("atlas", address(atlas)); // ATLAS == ESCROW
        console.log("escrow", address(escrow)); // ATLAS == ESCROW
        console.log("control", address(control));
        console.log("executionEnvironment", executionEnvironment);





        vm.startPrank(userEOA);
        // NOTE: Should metacall return something? Feels like a lot of data you might want to know about the tx
        atlas.metacall({
            protocolCall: protocolCall,
            userCall: userCall,
            searcherCalls: searcherCalls,
            verification: verification
        });
        vm.stopPrank();



    }

}