// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {IEscrow} from "../src/contracts/interfaces/IEscrow.sol";
import {IAtlas} from "../src/contracts/interfaces/IAtlas.sol";
import {IProtocolIntegration} from "../src/contracts/interfaces/IProtocolIntegration.sol";

import {Atlas} from "../src/contracts/atlas/Atlas.sol";
import {Mimic} from "../src/contracts/atlas/Mimic.sol";

import {V2ProtocolControl} from "../src/contracts/v2-example/V2ProtocolControl.sol";

import {Searcher} from "./searcher/src/TestSearcher.sol";

import "../src/contracts/types/CallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/VerificationTypes.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {V2Helper} from "./V2Helper.sol";
import {VerificationSigner} from "./VerificationSigner.sol";

import "forge-std/Test.sol";

contract MainTest is BaseTest {
    /// forge-config: default.gas_price = 15000000000
    function setUp() public virtual override {
        BaseTest.setUp();
    }

    // function testMain() public {
    //     uint8 v;
    //     bytes32 r;
    //     bytes32 s;

    //     ProtocolCall memory protocolCall = helper.getProtocolCall();

    //     UserCall memory userCall = helper.buildUserCall(POOL_ONE, userEOA, TOKEN_ONE);

    //     (v, r, s) = vm.sign(userPK, IAtlas(address(atlas)).getUserCallPayload(userCall));
    //     userCall.signature = abi.encodePacked(r, s, v);

    //     SearcherCall[] memory searcherCalls = new SearcherCall[](2);
    //     bytes memory searcherCallData;
    //     // First SearcherCall
    //     searcherCallData = helper.buildV2SearcherCallData(POOL_TWO, POOL_ONE);
    //     searcherCalls[1] =
    //         helper.buildSearcherCall(userCall, protocolCall, searcherCallData, searcherOneEOA, address(searcherOne), 2e17);

    //     (v, r, s) = vm.sign(searcherOnePK, IAtlas(address(atlas)).getSearcherPayload(searcherCalls[1].metaTx));
    //     searcherCalls[1].signature = abi.encodePacked(r, s, v);
        
    //     // Second SearcherCall
    //     searcherCallData = helper.buildV2SearcherCallData(POOL_ONE, POOL_TWO);
    //     searcherCalls[0] =
    //         helper.buildSearcherCall(userCall, protocolCall, searcherCallData, searcherTwoEOA, address(searcherTwo), 1e17);

    //     (v, r, s) = vm.sign(searcherTwoPK, IAtlas(address(atlas)).getSearcherPayload(searcherCalls[0].metaTx));
    //     searcherCalls[0].signature = abi.encodePacked(r, s, v);

    //     console.log("topBid before sorting",searcherCalls[0].bids[0].bidAmount);
        
    //     searcherCalls = sorter.sortBids(userCall, searcherCalls);

    //     console.log("topBid after sorting ",searcherCalls[0].bids[0].bidAmount);

    //     // Verification call
    //     Verification memory verification =
    //         helper.buildVerification(governanceEOA, protocolCall, userCall, searcherCalls);

    //     (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getVerificationPayload(verification));

    //     verification.signature = abi.encodePacked(r, s, v);

    //     vm.startPrank(userEOA);

    //     address executionEnvironment = IAtlas(address(atlas)).createExecutionEnvironment(protocolCall);
    //     vm.label(address(executionEnvironment), "EXECUTION ENV");

    //     console.log("userEOA", userEOA);
    //     console.log("atlas", address(atlas));
    //     console.log("control", address(control));
    //     console.log("executionEnvironment", executionEnvironment);

    //     // User must approve Atlas
    //     ERC20(TOKEN_ZERO).approve(address(atlas), type(uint256).max);
    //     ERC20(TOKEN_ONE).approve(address(atlas), type(uint256).max);

    //     uint256 userBalance = userEOA.balance;

    //     (bool success,) = address(atlas).call(
    //         abi.encodeWithSelector(
    //             atlas.metacall.selector, protocolCall, userCall, searcherCalls, verification
    //         )
    //     );

    //     assertTrue(success);
    //     console.log("user gas refund received",userEOA.balance - userBalance);
    //     console.log("user refund equivalent gas usage", (userEOA.balance - userBalance)/tx.gasprice);
        
    //     vm.stopPrank();

        /*
        console.log("");
        console.log("-");
        console.log("-");

        // Second attempt
        protocolCall = helper.getProtocolCall();

        userCall = helper.buildUserCall(POOL_ONE, userEOA, TOKEN_ONE);

        // First SearcherCall
        searcherCalls[0] =
            helper.buildSearcherCall(userCall, protocolCall, searcherOneEOA, address(searcherOne), POOL_ONE, POOL_TWO, 2e17);

        (v, r, s) = vm.sign(searcherOnePK, IAtlas(address(atlas)).getSearcherPayload(searcherCalls[0].metaTx));
        searcherCalls[0].signature = abi.encodePacked(r, s, v);

        // Second SearcherCall
        searcherCalls[1] =
            helper.buildSearcherCall(userCall, protocolCall, searcherTwoEOA, address(searcherTwo), POOL_TWO, POOL_ONE, 1e17);

        (v, r, s) = vm.sign(searcherTwoPK, IAtlas(address(atlas)).getSearcherPayload(searcherCalls[1].metaTx));
        searcherCalls[1].signature = abi.encodePacked(r, s, v);

        // Verification call
        verification =
            helper.buildVerification(governanceEOA, protocolCall, userCall, searcherCalls);

        (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getVerificationPayload(verification));

        verification.signature = abi.encodePacked(r, s, v);

        vm.startPrank(userEOA);

        executionEnvironment = IAtlas(address(atlas)).getExecutionEnvironment(userCall, address(control));
        
        userBalance = userEOA.balance;

        (success,) = address(atlas).call(
            abi.encodeWithSelector(
                atlas.metacall.selector, protocolCall, userCall, searcherCalls, verification
            )
        );

        assertTrue(success);
        console.log("user gas refund received",userEOA.balance - userBalance);
        console.log("user refund equivalent gas usage", (userEOA.balance - userBalance)/tx.gasprice);

        vm.stopPrank();
        */
    // }

    /*
    function testMimic() public {
        address aaaaa = address(this);
        address bbbbb = msg.sender;
        address ccccc = address(this);
        uint16 ddddd = uint16(0x1111);
        bytes32 eeeee = keccak256(abi.encodePacked(uint256(0x2222)));
        // Mimic mimic = new Mimic();
        //console.log("----");
        //console.log("runtime code:");
        //console.logBytes(address(mimic).code);
        console.log("aaaaa", aaaaa);
        console.log("bbbbb", bbbbb);
        console.log("ccccc", ccccc);
        console.logBytes32(eeeee);
        console.log("----");
        console.log("creation code:");
        console.logBytes(type(Mimic).creationCode);
        console.log("----");

        bytes memory creationCode = type(Mimic).creationCode;
        //bytes memory creationCode = new bytes(790);
        assembly {
            mstore(add(creationCode, 85), add(
                shl(96, aaaaa), 
                0x73ffffffffffffffffffffff
            ))
            mstore(add(creationCode, 131), add(
                shl(96, bbbbb), 
                0x73ffffffffffffffffffffff
            ))
            mstore(add(creationCode, 152), add(
                shl(96, ccccc), 
                add(
                    add(
                        shl(88, 0x61), 
                        shl(72, ddddd)
                    ),
                    0x7f0000000000000000
                )
            ))
            mstore(add(creationCode, 176), eeeee)
        }
        
        console.log("assembly modified code:");
        console.logBytes(creationCode);
        console.log("----");
    }
    */

    function testTestSearcherCall() public {
        uint8 v;
        bytes32 r;
        bytes32 s;

        ProtocolCall memory protocolCall = helper.getProtocolCall();
        UserCall memory userCall = helper.buildUserCall(POOL_ONE, userEOA, TOKEN_ONE);

        (v, r, s) = vm.sign(userPK, IAtlas(address(atlas)).getUserCallPayload(userCall));
        userCall.signature = abi.encodePacked(r, s, v);

        SearcherCall[] memory searcherCalls = new SearcherCall[](1);
        bytes memory searcherCallData = helper.buildV2SearcherCallData(POOL_TWO, POOL_ONE);
        searcherCalls[0] = helper.buildSearcherCall(
            userCall, protocolCall, searcherCallData, searcherOneEOA, address(searcherOne), 2e17
        );

        (v, r, s) = vm.sign(searcherOnePK, IAtlas(address(atlas)).getSearcherPayload(searcherCalls[0].metaTx));
        searcherCalls[0].signature = abi.encodePacked(r, s, v);

        // Verification call
        Verification memory verification =
            helper.buildVerification(governanceEOA, protocolCall, userCall, searcherCalls);

        (v, r, s) = vm.sign(governancePK, IAtlas(address(atlas)).getVerificationPayload(verification));
        verification.signature = abi.encodePacked(r, s, v);

        vm.startPrank(userEOA);

        address executionEnvironment = IAtlas(address(atlas)).createExecutionEnvironment(protocolCall);
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        // User must approve Atlas
        ERC20(TOKEN_ZERO).approve(address(atlas), type(uint256).max);
        ERC20(TOKEN_ONE).approve(address(atlas), type(uint256).max);

        (bool success,) = address(atlas).call(
            abi.encodeWithSelector(
                atlas.metacall.selector, protocolCall, userCall, searcherCalls, verification
            )
        );

        assertTrue(success);
        
        vm.stopPrank();
    }
}
