// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { ArbitrumGasCalculator } from "src/contracts/gasCalculator/ArbitrumGasCalculator.sol";

// Deploy script for the Arbitrum L2GasCalculator
contract SetArbGasCalculatorScript is DeployBaseScript {
    ArbitrumGasCalculator public gasCalculator = ArbitrumGasCalculator(0x870584178A64f409B00De32816D56756772E6cb4);

    // GAS CALCULATOR SETTINGS
    uint64 newA = 0;
    uint64 newB = 0;
    uint64 newR = 0;
    uint64 newC = 0;

    function run() external {
        console.log("\n=== DEPLOYING GasCalculator ===\n");

        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t", deployer);

        uint256 chainId = block.chainid;
        address deploymentAddr;

        (uint64 a, uint64 b, uint64 r, uint64 c) = gasCalculator.getCalibrationVars();

        console.log("old a:", a);
        console.log("old b:", b);
        console.log("old r:", r);
        console.log("old c:", c);

        vm.startBroadcast(deployerPrivateKey);

        // Check if chainId is Arbitrum One or Arbitrum Sepolia
        if (chainId == 42_161 || chainId == 421_614) {
            gasCalculator.setCalibrationVars(newA, newB, newR, newC);
        } else {
            revert("Error: Chain ID not supported");
        }

        vm.stopBroadcast();

        console.log("new a:", newA);
        console.log("new b:", newB);
        console.log("new r:", newR);
        console.log("new c:", newC);
    }
}
