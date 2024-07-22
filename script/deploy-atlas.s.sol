// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";
import { Sorter } from "src/contracts/helpers/Sorter.sol";
import { ExecutionEnvironment } from "src/contracts/common/ExecutionEnvironment.sol";

contract DeployAtlasScript is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        console.log("Deploying to chain: \t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Computes the addresses at which AtlasVerification will be deployed
        address expectedAtlasAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        address expectedAtlasVerificationAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);
        address expectedSimulatorAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 3);

        console.log("Deployer address: \t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment(expectedAtlasAddr);
        atlas = new Atlas({
            escrowDuration: 64,
            verification: expectedAtlasVerificationAddr,
            simulator: expectedSimulatorAddr,
            executionTemplate: address(execEnvTemplate),
            initialSurchargeRecipient: deployer,
            l2GasCalculator: address(0)
        });
        atlasVerification = new AtlasVerification(address(atlas));

        simulator = new Simulator();
        simulator.setAtlas(address(atlas));

        sorter = new Sorter(address(atlas));

        vm.stopBroadcast();

        bool error = false;

        // Check Atlas address set correctly everywhere
        if (address(atlas) != atlasVerification.ATLAS()) {
            console.log("ERROR: Atlas address not set correctly in AtlasVerification");
            error = true;
        }
        if (address(atlas) != simulator.atlas()) {
            console.log("ERROR: Atlas address not set correctly in Simulator");
            error = true;
        }
        if (address(atlas) != address(sorter.ATLAS())) {
            console.log("ERROR: Atlas address not set correctly in Sorter");
            error = true;
        }
        if (address(atlas) == address(0)) {
            console.log("ERROR: Atlas deployment address is 0x0");
            error = true;
        }
        // Check AtlasVerification address set correctly everywhere
        if (address(atlasVerification) != address(atlas.VERIFICATION())) {
            console.log("ERROR: AtlasVerification address not set correctly in Atlas");
            error = true;
        }
        if (address(atlasVerification) != address(sorter.VERIFICATION())) {
            console.log("ERROR: AtlasVerification address not set correctly in Sorter");
            error = true;
        }
        if (address(atlasVerification) == address(0)) {
            console.log("ERROR: AtlasVerification deployment address is 0x0");
            error = true;
        }
        // Check Simulator address set correctly in Atlas
        if (address(simulator) != atlas.SIMULATOR()) {
            console.log("ERROR: Simulator address not set correctly in Atlas");
            error = true;
        }
        if (address(simulator) == address(0)) {
            console.log("ERROR: Simulator deployment address is 0x0");
            error = true;
        }
        // Check Sorter address set correctly everywhere
        if (address(sorter) == address(0)) {
            console.log("ERROR: Sorter deployment address is 0x0");
            error = true;
        }
        // Check ESCROW_DURATION was not set to 0
        if (atlas.ESCROW_DURATION() == 0) {
            console.log("ERROR: ESCROW_DURATION was set to 0");
            error = true;
        }

        if (error) {
            console.log("ERROR: One or more addresses are incorrect. Exiting.");
            return;
        }

        _writeAddressToDeploymentsJson("ATLAS", address(atlas));
        _writeAddressToDeploymentsJson("ATLAS_VERIFICATION", address(atlasVerification));
        _writeAddressToDeploymentsJson("SIMULATOR", address(simulator));
        _writeAddressToDeploymentsJson("SORTER", address(sorter));

        // Print the table header
        console.log("\n");
        console.log("------------------------------------------------------------------------");
        console.log("| Contract              | Address                                      |");
        console.log("------------------------------------------------------------------------");
        console.log("| Atlas                 | ", address(atlas), " |");
        console.log("| AtlasVerification     | ", address(atlasVerification), " |");
        console.log("| Simulator             | ", address(simulator), " |");
        console.log("| Sorter                | ", address(sorter), " |");
        console.log("------------------------------------------------------------------------");
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
