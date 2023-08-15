// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {ProtocolCall, UserCall, SearcherCall} from "../src/contracts/types/CallTypes.sol";
import {Verification} from "../src/contracts/types/VerificationTypes.sol";

import {SwapIntentController, SwapIntent} from "src/contracts/intents-example/SwapIntent.sol";
import {SearcherBase} from "../src/contracts/searcher/SearcherBase.sol";

// QUESTIONS:

// Refactor Ideas:
// 1. Lots of bitwise operations explicitly coded in contracts - could be a helper lib thats more readable
// 2. helper is currently a V2Helper and shared from BaseTest. Should only be in Uni V2 related tests
// 3. Need a more generic helper for BaseTest
// 4. Gonna be lots of StackTooDeep errors. Maybe need a way to elegantly deal with that in BaseTest
// 5. Change metaFlashCall structure in SearcherBase - maybe virtual fn to be overridden, which hooks for checks

// Doc Ideas:
// 1. Step by step instructions for building a metacall transaction (for internal testing, and integrating protocols)

// To Understand Better:
// 1. The lock system (and look for any gas optimizations / ways to reduce lock actions)

contract SwapIntentTest is BaseTest {
    SwapIntentController public swapIntentController;
    TxBuilder public txBuilder;
    Sig public sig;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();

        swapIntentController = new SwapIntentController(address(escrow));

        txBuilder = new TxBuilder({
            protocolControl: address(swapIntentController),
            escrowAddress: address(escrow),
            atlasAddress: address(atlas)
        });
    }

    function testAtlasSwapUsingIntent() public {
        // Swap 10 WETH for 20 FXS
        SwapIntent memory swapIntent = SwapIntent({
            tokenUserBuys: FXS_ADDRESS,
            amountUserBuys: 20e18,
            tokenUserSells: WETH_ADDRESS,
            amountUserSells: 10e18,
            surplusToken: address(0)
        });

        // Searcher deploys the RFQ searcher contract (defined at bottom of this file)
        vm.prank(searcherOneEOA);
        SimpleRFQSearcher rfqSearcher = new SimpleRFQSearcher(address(atlas));
        // Give 20 FXS to RFQ searcher contract
        deal(FXS_ADDRESS, address(rfqSearcher), swapIntent.amountUserBuys);

        // Input params for Atlas.metacall() - will be populated below
        ProtocolCall memory protocolCall;
        UserCall memory userCall;
        SearcherCall[] memory searcherCalls = new SearcherCall[](1);
        Verification memory verification;

        protocolCall = txBuilder.getProtocolCall();

        // userCallData is used in delegatecall from exec env to control, calling stagingCall
        // first 4 bytes are "userSelector" param in stagingCall in ProtocolControl - swap() selector
        // rest of data is "userData" param
        
        // swap(SwapIntent calldata) selector = 0x98434997
        bytes memory userCallData = abi.encodeWithSelector(SwapIntentController.swap.selector, swapIntent);
        console.log("userCallData:");
        console.logBytes(userCallData);

        // Builds the metaTx and to parts of userCall, signature still to be set
        userCall = txBuilder.buildUserCall({
            from: userEOA, // NOTE: Would from ever not be user?
            to: address(atlas),
            maxFeePerGas: 0, // TODO update
            value: 0,
            data: userCallData
        });

        // User signs the userCall
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlas.getUserCallPayload(userCall));
        userCall.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // searcherCallData is similar to userCallData
        // decodes to [bytes stagingReturnData, address searcherTo]
        // where stagingReturnData decodes to SwapIntent (same as in userCallData)
        bytes memory searcherCallData = abi.encode(swapIntent, address(rfqSearcher));
        console.log("searcherCallData:");
        console.logBytes(searcherCallData);

        // TODO need a way to pass function selector and params of searcher contract in searcherCallData
        // Not sure if the SwapIntent controller is set up to do that and the SwapIntent data obj
        // The data below is also needed I think:
        bytes memory extraSearcherCallData = abi.encodeWithSelector(
            SimpleRFQSearcher.fulfillRFQ.selector, 
            WETH_ADDRESS,
            swapIntent.amountUserSells,
            FXS_ADDRESS,
            swapIntent.amountUserBuys
        );
        console.log("extra searcherCallData:");
        console.logBytes(extraSearcherCallData);

        // Builds the SearcherCall
        searcherCalls[0] = txBuilder.buildSearcherCall({
            userCall: userCall,
            protocolCall: protocolCall,
            searcherCallData: searcherCallData, // TODO need searcher contract and function to execute
            searcherEOA: searcherOneEOA,
            searcherContract: address(rfqSearcher),
            bidAmount: 1e18
        });

        // Searcher signs the searcherCall
        (sig.v, sig.r, sig.s) = vm.sign(searcherOnePK, atlas.getSearcherPayload(searcherCalls[0].metaTx));
        searcherCalls[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Frontend creates verification calldata after seeing rest of data
        verification = txBuilder.buildVerification(governanceEOA, protocolCall, userCall, searcherCalls);

        // Frontend signs the verification payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlas.getVerificationPayload(verification));
        verification.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        address executionEnvironment = atlas.createExecutionEnvironment(protocolCall);
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        console.log("userEOA", userEOA);
        console.log("atlas", address(atlas)); // ATLAS == ESCROW
        console.log("escrow", address(escrow)); // ATLAS == ESCROW
        console.log("control", address(control));
        console.log("executionEnvironment", executionEnvironment);

        // Check user token balances before
        uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);
        uint256 userFxsBalanceBefore = FXS.balanceOf(userEOA);

        console.log("userWethBalanceBefore", userWethBalanceBefore);
        console.log("userFxsBalanceBefore", userFxsBalanceBefore);
        assertTrue(userWethBalanceBefore > swapIntent.amountUserSells, "Not enough starting WETH");

        vm.startPrank(userEOA);
        // User approves Atlas to take 10 WETH
        WETH.approve(address(atlas), swapIntent.amountUserSells);
        
        // NOTE: Should metacall return something? Feels like a lot of data you might want to know about the tx
        atlas.metacall({
            protocolCall: protocolCall,
            userCall: userCall,
            searcherCalls: searcherCalls,
            verification: verification
        });
        vm.stopPrank();

        // Check user token balances after
        assertEq(WETH.balanceOf(userEOA), userWethBalanceBefore - swapIntent.amountUserSells, "Did not spend enough WETH");
        assertEq(FXS.balanceOf(userEOA), userFxsBalanceBefore + swapIntent.amountUserBuys, "Did not receive enough FXS");
    }
}


contract SimpleRFQSearcher is SearcherBase {

    address public immutable owner;

    constructor(address atlas) SearcherBase(atlas, msg.sender) {
        owner = msg.sender;
    }

    function fulfillRFQ(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    ) public {
        require(ERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Did not receive enough tokenIn");
        require(ERC20(tokenOut).balanceOf(address(this)) >= amountOut, "Not enough tokenOut to fulfill");

        ERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}