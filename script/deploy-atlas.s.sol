// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasFactory } from "src/contracts/atlas/AtlasFactory.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { SwapIntentController } from "src/contracts/examples/intents-example/SwapIntent.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";

contract DeployAtlasScript is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        console.log("Deploying to chain: ", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // Computes the addresses at which AtlasFactory and AtlasVerification will be deployed
        address expectedAtlasFactoryAddr = computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        address expectedAtlasVerificationAddr = computeCreateAddress(deployer, vm.getNonce(deployer) + 2);
        address expectedBoAtlETHAddr = computeCreateAddress(deployer, vm.getNonce(deployer) + 3);
        address expectedSimulatorAddr = computeCreateAddress(deployer, vm.getNonce(deployer) + 4);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        atlas = new Atlas({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _boAtlETH: expectedBoAtlETHAddr,
            _simulator: expectedSimulatorAddr
        });
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));

        simulator = new Simulator();
        simulator.setAtlas(address(atlas));

        vm.stopBroadcast();

        if (address(atlas) != simulator.atlas() || address(atlas) != atlasVerification.ATLAS()) {
            console.log("ERROR: Atlas address not set correctly in Simulator, AtlasVerification");
        }
        if (address(atlasFactory) != atlas.FACTORY()) {
            console.log("ERROR: AtlasFactory address not set correctly in Atlas");
        }
        if (address(atlasVerification) != atlas.VERIFICATION()) {
            console.log("ERROR: AtlasVerification address not set correctly in Atlas");
        }
        if (address(simulator) != atlas.SIMULATOR()) {
            console.log("ERROR: Simulator address not set correctly in Atlas");
        }

        _writeAddressToDeploymentsJson("ATLAS", address(atlas));
        _writeAddressToDeploymentsJson("ATLAS_FACTORY", address(atlasFactory));
        _writeAddressToDeploymentsJson("ATLAS_VERIFICATION", address(atlasVerification));
        _writeAddressToDeploymentsJson("SIMULATOR", address(simulator));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("AtlasFactory deployed at: \t\t\t", address(atlasFactory));
        console.log("AtlasVerification deployed at: \t\t", address(atlasVerification));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
