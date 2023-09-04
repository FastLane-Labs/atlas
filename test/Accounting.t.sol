// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";


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
