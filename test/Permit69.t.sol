// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";

import {ProtocolCall, UserCall, SearcherCall} from "../src/contracts/types/CallTypes.sol";
import {Verification} from "../src/contracts/types/VerificationTypes.sol";



contract Permit69Test is BaseTest {

    function setUp() public virtual override {
        BaseTest.setUp();
    }

    // transferUserERC20 tests

    function testTransferUserERC20RevertsIfCallerNotExecutionEnv() public {}

    function testTransferUserERC20RevertsIfLockStateNotValid() public {}

    function testTransferUserERC20SuccessfullyTransfersTokens() public {}

    // transferProtocolERC20 tests

    function testTransferProtocolERC20RevertsIfCallerNotExecutionEnv() public {}

    function testTransferProtocolERC20RevertsIfLockStateNotValid() public {}

    function testTransferProtocolERC20SuccessfullyTransfersTokens() public {}



}