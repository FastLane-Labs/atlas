// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { ArbitrumGasCalculator } from "../src/contracts/gasCalculator/ArbitrumGasCalculator.sol";
import { ArbitrumTest } from "./Arbitrum.t.sol";

contract ArbitrumGasCalculatorTest is ArbitrumTest {

    function setUp() public virtual override {
        // Arbitrum.t.sol's setUp handles forking Arbitrum
        // and deploying the Arbitrum L2GasCalculator
        super.setUp();
    }

    function test_ArbitrumGasCalculator_TEMP() public {
    
    }
}
