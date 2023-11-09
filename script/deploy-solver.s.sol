// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {DeployBaseScript} from "script/base/deploy-base.s.sol";
import {SimpleRFQSolver} from "test/SwapIntent.t.sol";

contract DeploySimpleRFQSolverScript is DeployBaseScript {
    SimpleRFQSolver public rfqSolver;


    function run() external {
        console.log("\n=== DEPLOYING SimpleRFQSolver ===\n");

        uint256 deployerPrivateKey = vm.envUint("SOLVER1_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address atlasAddress = _getAddressFromDeploymentsJson("ATLAS");

        console.log("Deployer address: \t\t\t\t", deployer);
        console.log("Using Atlas address: \t\t\t\t", atlasAddress);

        vm.startBroadcast(deployerPrivateKey);

        rfqSolver = new SimpleRFQSolver(atlasAddress);

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson("SIMPLE_RFQ_SOLVER", address(rfqSolver));

        console.log("\n");
        console.log("SimpleRFQSolver deployed at: \t\t\t", address(rfqSolver));
    }
}