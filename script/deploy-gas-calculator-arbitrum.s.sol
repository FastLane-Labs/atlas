// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { ArbitrumGasCalculator } from "src/contracts/gasCalculator/ArbitrumGasCalculator.sol";
import { ChainConfig } from "src/contracts/libraries/ChainConfig.sol";

// Deploy script for the Arbitrum L2GasCalculator
contract DeployArbGasCalculatorScript is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING GasCalculator ===\n");

        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t", deployer);

        address deploymentAddr;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ArbitrumGasCalculator only for Arbitrum chains
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            ArbitrumGasCalculator arbitrumGasCalc = new ArbitrumGasCalculator();
            deploymentAddr = address(arbitrumGasCalc);
            console.log("Arbitrum Gas Calculator deployed at: ", deploymentAddr);
        } else {
            revert("Error: This script is only for Arbitrum chains (42161, 421614)");
        }

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson("L2_GAS_CALCULATOR", deploymentAddr);

        console.log("\n");
        console.log("-------------------------------------------------------------------------------");
        console.log("| Contract                     | Address                                       |");
        console.log("-------------------------------------------------------------------------------");
        console.log("| L2_GAS_CALCULATOR (Arbitrum) | ", address(deploymentAddr), "  |");
        console.log("-------------------------------------------------------------------------------");
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
