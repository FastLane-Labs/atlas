// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasFactory } from "src/contracts/atlas/AtlasFactory.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { SwapIntentController } from "src/contracts/examples/intents-example/SwapIntent.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";
import { SimpleRFQSolver } from "test/SwapIntent.t.sol";

import { Utilities } from "src/contracts/helpers/Utilities.sol";

contract DeployBaseScript is Script {
    using stdJson for string;

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    Simulator public simulator;
    SwapIntentController public swapIntentControl;
    TxBuilder public txBuilder;
    SimpleRFQSolver public rfqSolver;

    Utilities public u;

    function _getDeployChain() internal view returns (string memory) {
        // OPTIONS: LOCAL, SEPOLIA, MAINNET
        string memory deployChain = vm.envString("DEPLOY_TO");
        if (
            keccak256(bytes(deployChain)) == keccak256(bytes("SEPOLIA"))
                || keccak256(bytes(deployChain)) == keccak256(bytes("MAINNET"))
                || keccak256(bytes(deployChain)) == keccak256(bytes("LOCAL"))
        ) {
            return deployChain;
        } else {
            revert("Error: Set DEPLOY_TO in .env to LOCAL, SEPOLIA, or MAINNET");
        }
    }

    // NOTE: When handling JSON with StdJson, prefix keys with '.' e.g. '.ATLAS'
    // These 2 functions abstract away the '.' thing though.
    // Just pass in a key like 'ATLAS' and set DEPLOY_TO in .env to LOCAL, SEPOLIA, or MAINNET
    function _getAddressFromDeploymentsJson(string memory key) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);

        // Read target chain from DEPLOY_TO in .env and use to form full key
        string memory fullKey = string.concat(".", _getDeployChain(), ".", key);

        // console.log("Getting", fullKey, "from deployments.json");

        // NOTE: Use fullKey method above for safety
        return json.readAddress(fullKey);
    }

    function _writeAddressToDeploymentsJson(string memory key, address addr) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");

        // Read target chain from DEPLOY_TO in .env and use to form full key
        string memory fullKey = string.concat(".", _getDeployChain(), ".", key);

        // console.log(string.concat("Writing \t\t'", fullKey), "': '", addr, "'\t\t to deployments.json");

        // NOTE: Use fullKey method above for safety
        vm.writeJson(vm.toString(addr), path, fullKey);
    }

    function _logTokenBalances(address account, string memory accountLabel) internal view {
        console.log("Balances for", accountLabel);
        console.log("WETH balance: \t\t\t\t", WETH.balanceOf(account));
        console.log("DAI balance: \t\t\t\t\t", DAI.balanceOf(account));
        console.log("\n");
    }
}
