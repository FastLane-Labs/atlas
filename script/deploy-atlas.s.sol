// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {DeployBaseScript} from "script/base/deploy-base.s.sol";

import {Atlas} from "src/contracts/atlas/Atlas.sol";
import {SwapIntentController} from "src/contracts/examples/intents-example/SwapIntent.sol";
import {TxBuilder} from "src/contracts/helpers/TxBuilder.sol";

contract DeployAtlasScript is DeployBaseScript {
    Atlas public atlas;

    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        atlas = new Atlas(64, address(0));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
    }
}

contract DeployAtlasAndSwapIntentDAppControlScript is DeployBaseScript {
    Atlas public atlas;
    SwapIntentController public swapIntentControl;

    function run() external {
        console.log("\n=== DEPLOYING Atlas and SwapIntent DAppControl ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the Atlas contract
        atlas = new Atlas(64, address(0));

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlas.initializeGovernance(address(swapIntentControl));
        atlas.integrateDApp(address(swapIntentControl), address(swapIntentControl));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SWAP_INTENT_DAPP_CONTROL", address(swapIntentControl));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
    }
}

contract DeployAtlasAndSwapIntentDAppControlAndTxBuilderScript is DeployBaseScript {
    Atlas public atlas;
    SwapIntentController public swapIntentControl;
    TxBuilder public txBuilder;

    function run() external {
        console.log("\n=== DEPLOYING Atlas and SwapIntent DAppControl and TxBuilder ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the Atlas contract
        atlas = new Atlas(64, address(0));

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlas.initializeGovernance(address(swapIntentControl));
        atlas.integrateDApp(address(swapIntentControl), address(swapIntentControl));

        // Deploy the TxBuilder
        txBuilder = new TxBuilder(address(swapIntentControl), address(atlas), address(atlas));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SWAP_INTENT_DAPP_CONTROL", address(swapIntentControl));
        _writeAddressToDeploymentsJson(".TX_BUILDER", address(txBuilder));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
        console.log("TxBuilder deployed at: \t\t\t", address(txBuilder));
    }
}
