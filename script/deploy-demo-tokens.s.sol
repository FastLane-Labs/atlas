// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { V2RewardDAppControl } from "src/contracts/examples/v2-example-router/V2RewardDAppControl.sol";
import { IUniswapV2Router02 } from "src/contracts/examples/v2-example-router/interfaces/IUniswapV2Router.sol";

import { Token } from "src/contracts/helpers/DemoToken.sol";

// Deploy 3 stablecoin tokens (DAI, USDA, USDB) - all 18 decimals
// Deploy a WETH token
// Make WETH/Stable pools on Uniswap V2 for each stablecoin
// Add liquidity to each pool: 3_000_000 Stablecoin / 1_000 WETH = $3000 per WETH

contract DeployDemoTokensScript is DeployBaseScript {
    address public constant UNISWAP_V2_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008; // on Sepolia
    address public constant UNISWAP_V2_FACTORY = 0x7E0987E5b3a30e3f2828572Bb659A548460a3003; // on Sepolia

    Token dai;
    Token usda;
    Token usdb;
    Token weth;

    function run() external {
        console.log("\n=== DEPLOYING DEMO TOKENS ===\n");

        uint256 deployerPrivateKey = vm.envUint("DAPP_GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy 3 stablecoins and WETH
        console.log("Deploying tokens...\n");
        dai = new Token("DAI Stablecoin", "DAI", 18);
        usda = new Token("USDA Stablecoin", "USDA", 18);
        usdb = new Token("USDB Stablecoin", "USDB", 18);
        weth = new Token("Wrapped Ether", "WETH", 18);

        // Create WETH/Stablecoin pools on Uniswap V2
        console.log("Creating Uniswap V2 Pools...\n");
        address daiWethPool = IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(dai), address(weth));
        address usdaWethPool = IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(usda), address(weth));
        address usdbWethPool = IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(usdb), address(weth));
        address daiUsdaPool = IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(dai), address(usda));
        address daiUsdbPool = IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(dai), address(usdb));
        address usdaUsdbPool = IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(usda), address(usdb));

        // Add liquidity to stablecoin/weth pools: 3_000_000 Stablecoin / 1_000 WETH = $3000 per WETH
        console.log("Adding liquidity to STABLE/WETH pools...\n");
        mintApproveAndAddLiquidity(dai, weth, 3_000_000 ether, 1000 ether, deployer);
        mintApproveAndAddLiquidity(usda, weth, 3_000_000 ether, 1000 ether, deployer);
        mintApproveAndAddLiquidity(usdb, weth, 3_000_000 ether, 1000 ether, deployer);

        // Add liquidity to stablecoin/stablecoin pools: 3_000_000 Stablecoin / 3_000_000 Stablecoin = 1:1
        console.log("Adding liquidity to STABLE/STABLE pools...\n");
        mintApproveAndAddLiquidity(dai, usda, 3_000_000 ether, 3_000_000 ether, deployer);
        mintApproveAndAddLiquidity(dai, usdb, 3_000_000 ether, 3_000_000 ether, deployer);
        mintApproveAndAddLiquidity(usda, usdb, 3_000_000 ether, 3_000_000 ether, deployer);

        vm.stopBroadcast();

        console.log("\n");
        console.log("DAI deployed at: \t\t", address(dai));
        console.log("USDA deployed at: \t\t", address(usda));
        console.log("USDB deployed at: \t\t", address(usdb));
        console.log("WETH deployed at: \t\t", address(weth));
        console.log("\n");
        console.log("DAI/WETH Pool: \t\t", daiWethPool);
        console.log("USDA/WETH Pool: \t\t", usdaWethPool);
        console.log("USDB/WETH Pool: \t\t", usdbWethPool);
        console.log("DAI/USDA Pool: \t\t", daiUsdaPool);
        console.log("DAI/USDB Pool: \t\t", daiUsdbPool);
        console.log("USDA/USDB Pool: \t\t", usdaUsdbPool);
        console.log("\n");
    }

    function mintApproveAndAddLiquidity(
        Token tokenA,
        Token tokenB,
        uint256 amountA,
        uint256 amountB,
        address deployer
    )
        public
    {
        tokenA.mint(deployer, amountA);
        tokenB.mint(deployer, amountB);

        tokenA.approve(UNISWAP_V2_ROUTER, amountA);
        tokenB.approve(UNISWAP_V2_ROUTER, amountB);

        IUniswapV2Router02(UNISWAP_V2_ROUTER).addLiquidity(
            address(tokenA), address(tokenB), amountA, amountB, amountA, amountB, deployer, block.timestamp + 50
        );
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
