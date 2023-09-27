// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {Atlas} from "src/contracts/atlas/Atlas.sol";
import {SwapIntentController} from "src/contracts/examples/intents-example/SwapIntent.sol";
import {SimpleRFQSolver} from "test/SwapIntent.t.sol"; // TODO move to searcher script

contract DeployAtlasScript is Script {
    Atlas public atlas;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        atlas = new Atlas(64);

        vm.stopBroadcast();

        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
    }
}

contract DeployAtlasAndSwapIntentDAppControlScript is Script {
    Atlas public atlas;
    SwapIntentController public swapIntentControl;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the Atlas contract
        atlas = new Atlas(64);

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlas.initializeGovernance(address(swapIntentControl));
        atlas.integrateDApp(address(swapIntentControl), address(swapIntentControl));

        vm.stopBroadcast();

        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
    }
}