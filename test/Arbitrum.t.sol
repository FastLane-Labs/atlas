// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

// Tests for Arbitrum-specific factors related to Atlas:
// - Getting the correct L2 block number using ArbSys precompile via SafeBlockNumber lib
// - Calldata gas estimation using ArbGasInfo precompile via Arbitrum L2GasCalculator
contract SimulatorTest is BaseTest {



    function setUp() public override {
        BaseTest.setUp();
    }

}