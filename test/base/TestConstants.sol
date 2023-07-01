// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IUniswapV2Pair} from "../../src/contracts/v2-example/interfaces/IUniswapV2Pair.sol";

contract TestConstants {

    uint256 constant public BLOCK_START = 17441786;

    // MAINNET
    ChainVars public MAINNET = ChainVars({RPC_URL_KEY: "MAINNET_RPC_URL", FORK_BLOCK: BLOCK_START});

    // Structs
    struct ChainVars {
        string RPC_URL_KEY;
        uint256 FORK_BLOCK;
    }

    // Constants
    address constant public FXS_ADDRESS = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address constant public WETH_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 constant public FXS = ERC20(FXS_ADDRESS);
    ERC20 constant public WETH = ERC20(WETH_ADDRESS);

    address constant public V2_FXS_ETH = address(0xecBa967D84fCF0405F6b32Bc45F4d36BfDBB2E81);
    address constant public S2_FXS_ETH = address(0x61eB53ee427aB4E007d78A9134AaCb3101A2DC23);

    address constant public POOL_ONE = V2_FXS_ETH;
    address constant public POOL_TWO = S2_FXS_ETH;
}
