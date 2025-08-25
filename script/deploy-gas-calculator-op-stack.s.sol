// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { BaseGasCalculator } from "src/contracts/gasCalculator/BaseGasCalculator.sol";
import { ChainConfig } from "src/contracts/libraries/ChainConfig.sol";

// Deploy script for the OP Stack L2GasCalculator - for Optimism, Base, Unichain, and other OP Stack L2s
contract DeployOPStackGasCalculatorScript is DeployBaseScript {
    // NOTE: Adjust the constructor parameters as needed here:
    // - OP_STACK_GAS_PRICE_ORACLE: The address of the gas price oracle contract (same for all OP Stack chains)
    // - OP_STACK_CALLDATA_LENGTH_OFFSET: The offset to be applied to the calldata length (can be negative or positive)
    // -----------------------------------------------------------------------------------------------
    address constant OP_STACK_GAS_PRICE_ORACLE = address(0x420000000000000000000000000000000000000F);
    int256 constant OP_STACK_CALLDATA_LENGTH_OFFSET = 0; // can be negative or positive
    // -----------------------------------------------------------------------------------------------

    function run() external {
        console.log("\n=== DEPLOYING GasCalculator ===\n");

        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t", deployer);

        address deploymentAddr;

        vm.startBroadcast(deployerPrivateKey);

        // Check if this chain is an OP Stack chain and requires an L2 gas calculator
        if (ChainConfig.requiresL2GasCalculator(block.chainid)) {
            // OP Stack chains: Optimism, Base, Unichain (mainnet and testnets)
            BaseGasCalculator gasCalculator = new BaseGasCalculator({
                gasPriceOracle: OP_STACK_GAS_PRICE_ORACLE,
                calldataLenOffset: OP_STACK_CALLDATA_LENGTH_OFFSET
            });
            deploymentAddr = address(gasCalculator);
        } else {
            revert("Error: Chain ID not supported for OP Stack gas calculator");
        }

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson("L2_GAS_CALCULATOR", deploymentAddr);

        console.log("\n");
        console.log("-------------------------------------------------------------------------------");
        console.log("| Contract                    | Address                                       |");
        console.log("-------------------------------------------------------------------------------");
        console.log("| L2_GAS_CALCULATOR (OP Stack) | ", address(deploymentAddr), "  |");
        console.log("-------------------------------------------------------------------------------");
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
