// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {SampleContract} from "../src/SampleContract.sol";

contract SampleContractTest is Test {
    SampleContract sampleContract;

    function setUp() public {
        sampleContract = new SampleContract();
    }

    function testFunc1() public {
        sampleContract.func1(1337);
    }

    function testFunc2() public {
        sampleContract.func2(1337);
    }
}
