// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ArbSys } from "nitro-contracts/src/precompiles/ArbSys.sol";

library SafeBlockNumber {
    // https://arbiscan.io/address/0x0000000000000000000000000000000000000064
    ArbSys internal constant ARB_SYS = ArbSys(address(0x0000000000000000000000000000000000000064));

    function get(bool useArbSys) internal view returns (uint256) {
        if (useArbSys) {
            return ARB_SYS.arbBlockNumber();
        } else {
            return block.number;
        }
    }

    // TODO this still bloats Atlas contract size even when just used in constructor. Will need to pass in true/false as
    // a constructor arg
    function isArbitrumStack() internal view returns (bool) {
        uint256 chainId = block.chainid;
        return (
            chainId == 42_161 // Arbitrum One
                || chainId == 42_170 // Arbitrum Nova
                || chainId == 421_614 // Arbitrum Sepolia
                || chainId == 98_866 // Plume
                || chainId == 98_867
        ); // Plume Testnet
    }
}
