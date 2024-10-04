// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ArbSys } from "nitro-contracts/src/precompiles/ArbSys.sol";
import { console } from "forge-std/console.sol";

library SafeBlockNumber {
    ArbSys internal constant arbsys = ArbSys(address(0x0000000000000000000000000000000000000064));

    uint256 internal constant ARBITRUM_ONE_CHAIN_ID = 42_161;
    uint256 internal constant ARBITRUM_NOVA_CHAIN_ID = 42_170;

    function get() internal view returns (uint256) {
        if (block.chainid == ARBITRUM_ONE_CHAIN_ID || block.chainid == ARBITRUM_NOVA_CHAIN_ID) {
            // Arbitrum One or Nova chain
            return arbsys.arbBlockNumber();
        } else {
            return block.number;
        }
    }
}
