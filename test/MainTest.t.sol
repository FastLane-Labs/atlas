// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {IEscrow} from "../src/contracts/interfaces/IEscrow.sol";
import {IProtocolIntegration} from "../src/contracts/interfaces/IProtocolIntegration.sol";

import {Atlas} from "../src/contracts/atlas/Atlas.sol";

import {V2ProtocolControl} from "../src/contracts/v2-example/V2ProtocolControl.sol";


import {Searcher} from "./searcher/src/TestSearcher.sol";

import "../src/contracts/types/CallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/VerificationTypes.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {Helper} from "./Helpers.sol";

contract MainTest is BaseTest {
    function setUp() public virtual override {
        BaseTest.setUp();
    }

    function testMain() public {
        
        vm.label(userEOA, "user");
        vm.label(escrow, "escrow");
        vm.label(address(atlas), "atlas");
        vm.label(address(control), "pcontrol");
        
        ProtocolCall memory protocolCall = helper.getProtocolCall();
        
        UserCall memory userCall = helper.buildUserCall(POOL_ONE, userEOA, 0, 1E23);
        
        PayeeData[] memory payeeData = helper.getPayeeData();

        SearcherCall[] memory searcherCalls = new SearcherCall[](2);

        searcherCalls[0] = helper.buildSearcherCall(
            userCall, searcherOneEOA, address(searcherOne), 1E15
        );
        searcherCalls[1] = helper.buildSearcherCall(
            userCall, searcherTwoEOA, address(searcherTwo), 2E15
        );
        
        Verification memory verification = helper.buildVerification(
            governanceEOA,
            protocolCall,
            userCall,
            payeeData,
            searcherCalls
        );

        vm.startPrank(userEOA);

        (bool success,) = address(atlas).call(
            abi.encodeWithSelector(
                atlas.metacall.selector, 
                protocolCall,
                userCall,
                payeeData,
                searcherCalls,
                verification
            )
        );
        assertTrue(success);
    }

    function buildUserCall() public returns (UserCall memory userCall) {

    }   
}