// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { BaseGasCalculator } from "src/contracts/gasCalculator/BaseGasCalculator.sol";

contract DeployGasCalculatorScript is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING GasCalculator ===\n");

        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory deploymentName;
        address deploymentAddr;

        vm.startBroadcast(deployerPrivateKey);

        if (chainId == 8453 || chainId == 84_532) {
            // Base or Base Sepolia
            BaseGasCalculator gasCalculator = new BaseGasCalculator({
                _gasPriceOracle: address(0), // Insert gas price oracle address here
                _calldataLengthOffset: 0 // Insert calldata length offset here (can be negative)
             });
            deploymentName = "BASE_GAS_CALCULATOR";
            deploymentAddr = address(gasCalculator);
        } else {
            revert("Error: Chain ID not supported");
        }

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(deploymentName, deploymentAddr);

        console.log("\n");
        console.log("Deployed contract: ", deploymentName);
        console.log("Deployed at address: ", deploymentAddr);
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
