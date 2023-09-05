// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";

import {SwapIntentController, SwapIntent} from "../src/contracts/intents-example/SwapIntent.sol";

import {SearcherBase} from "../src/contracts/searcher/SearcherBase.sol";



contract Permit69Test is BaseTest {
    function setUp() public virtual override {
        BaseTest.setUp();
    }


    function testSearcherEthValueIsNotDoubleCountedViaSurplusAccounting() public {

        // TODO
        // Define metacall where signer pays 2 ETH in msg.value
        // Define searcher (attacker) who requires 1 ETH in their searcher value param
        // Use SwapIntent as ProtocolControl because calls donateToBundler(searcherAddress)

        // See donateToBundler() function in Escrow.sol
        // which is called by Exec Env
        // which delegatecalls donateToBundler in a ProtocolControl contract e.g. SwapIntent (_searcherPostCall)


        // Criteria for this exploit to work:
        // 1. Some ETH must be sent via msg.value in the metacall (???)
        // 2. The ProtocolControl contract must call donateToBundler(searcherAddress)

    }

}


// This searcher magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
contract SimpleRFQSearcher is SearcherBase {
    constructor(address atlas) SearcherBase(atlas, msg.sender) {}

    function fulfillRFQ(
        SwapIntent calldata swapIntent,
        address executionEnvironment
    ) public payable {
        console.log("msg.value in searcher", msg.value);
        require(ERC20(swapIntent.tokenUserSells).balanceOf(address(this)) >= swapIntent.amountUserSells, "Did not receive enough tokenIn");
        require(ERC20(swapIntent.tokenUserBuys).balanceOf(address(this)) >= swapIntent.amountUserBuys, "Not enough tokenOut to fulfill");
        ERC20(swapIntent.tokenUserBuys).transfer(executionEnvironment, swapIntent.amountUserBuys);
    }

    // This ensures a function can only be called through metaFlashCall
    // which includes security checks to work safely with Atlas
    modifier onlySelf() {
        require(msg.sender == address(this), "Not called via metaFlashCall");
        _;
    }

    fallback() external payable {}
    receive() external payable {}
}