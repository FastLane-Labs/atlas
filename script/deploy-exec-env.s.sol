// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {DeployBaseScript} from "script/base/deploy-base.s.sol";

contract DeployExecEnvScript is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING Execution Environment ===\n");

        console.log("Deploying to chain: ", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // TODO 

        vm.stopBroadcast();

        // _writeAddressToDeploymentsJson("EXECUTION_ENV", address(simulator)); // TODO

        console.log("\n");
        // console.log("Execution Environment deployed at: \t\t\t\t", address(atlas)); // TODO
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
