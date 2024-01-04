// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { IUniswapV2Pair } from "../../src/contracts/examples/v2-example/interfaces/IUniswapV2Pair.sol";

contract TestConstants {
    uint256 public constant BLOCK_START = 17_441_786;

    // Structs
    struct ChainVars {
        string rpcUrlKey;
        uint256 forkBlock;
        address weth;
        address dai;
    }

    // MAINNET
    ChainVars public mainnet = ChainVars({
        rpcUrlKey: "MAINNET_RPC_URL",
        forkBlock: BLOCK_START,
        weth: address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
        dai: address(0x6B175474E89094C44Da98b954EedeAC495271d0F)
    });

    // Constants
    address public constant FXS_ADDRESS = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address public constant WETH_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 public constant FXS = ERC20(FXS_ADDRESS);
    ERC20 public constant WETH = ERC20(WETH_ADDRESS);

    address public constant V2_FXS_ETH = address(0xecBa967D84fCF0405F6b32Bc45F4d36BfDBB2E81);
    address public constant S2_FXS_ETH = address(0x61eB53ee427aB4E007d78A9134AaCb3101A2DC23);

    address public constant POOL_ONE = V2_FXS_ETH;
    address public constant POOL_TWO = S2_FXS_ETH;
    address public constant TOKEN_ZERO = FXS_ADDRESS;
    address public constant TOKEN_ONE = WETH_ADDRESS;
}
