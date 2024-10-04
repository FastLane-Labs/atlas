// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeBlockNumber } from "src/contracts/libraries/SafeBlockNumber.sol";

import { BaseTest } from "../base/BaseTest.t.sol";
import { ArbSysMock } from "./ArbSysMock.sol";

abstract contract ArbitrumTest is BaseTest {
    ArbSysMock internal constant arbsys = ArbSysMock(address(0x64));
    uint256 public constant ARBITRUM_BLOCK_NUMBER = 260_145_837;

    function setUp() public virtual override {
        super.setUpChain("ARBITRUM_RPC_URL", ARBITRUM_BLOCK_NUMBER);
        vm.etch(address(0x64), type(ArbSysMock).runtimeCode);
        arbsys.setArbBlockNumber(ARBITRUM_BLOCK_NUMBER);
    }
}


