// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "./base/deploy-base.s.sol";
import { GasCalculatorDeployHelper } from "./deploy-gas-calculator.s.sol";

import { FactoryLib } from "../src/contracts/atlas/FactoryLib.sol";
import { Atlas } from "../src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";
import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";
import { Simulator } from "../src/contracts/helpers/Simulator.sol";
import { Sorter } from "../src/contracts/helpers/Sorter.sol";
import { ExecutionEnvironment } from "../src/contracts/common/ExecutionEnvironment.sol";

contract DeployAtlasScript is DeployBaseScript, GasCalculatorDeployHelper {
    uint256 ESCROW_DURATION = 64;
    uint256 ATLAS_SURCHARGE_RATE = 1_000_000; // 10%
    uint256 BUNDLER_SURCHARGE_RATE = 1_000_000; // 10%

    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Computes the addresses at which AtlasVerification will be deployed
        address expectedAtlasAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);
        address expectedAtlasVerificationAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 3);
        address expectedSimulatorAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 4);

        // Deploy gas calculator for Arbitrum chains after other deployments
        address l2GasCalculatorAddr = _predictGasCalculatorAddress(deployer, vm.getNonce(deployer) + 5);
        // TODO return either addr(0) or predicted addr, depending on chainid. From GasCalculatorDeployer

        address prevSimAddr = _getAddressFromDeploymentsJson("SIMULATOR");
        uint256 prevSimBalance = (prevSimAddr == address(0)) ? 0 : prevSimAddr.balance;

        console.log("Deployer address: \t\t", deployer);
        console.log("Prev Simulator address: \t", prevSimAddr);
        console.log("Prev Simulator balance: \t", prevSimBalance);

        vm.startBroadcast(deployerPrivateKey);

        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment(expectedAtlasAddr);
        FactoryLib factoryLib = new FactoryLib(address(execEnvTemplate));
        atlas = new Atlas({
            escrowDuration: ESCROW_DURATION,
            atlasSurchargeRate: ATLAS_SURCHARGE_RATE,
            bundlerSurchargeRate: BUNDLER_SURCHARGE_RATE,
            verification: expectedAtlasVerificationAddr,
            simulator: expectedSimulatorAddr,
            factoryLib: address(factoryLib),
            initialSurchargeRecipient: deployer,
            l2GasCalculator: l2GasCalculatorAddr // is address(0) if not on Arbitrum
         });
        atlasVerification = new AtlasVerification(address(atlas));

        simulator = new Simulator();
        simulator.setAtlas(address(atlas));

        // If prev Simulator deployment has native assets, withdraw them to new Simulator
        if (prevSimBalance > 0) {
            Simulator(payable(prevSimAddr)).withdrawETH(address(simulator));
        }

        sorter = new Sorter(address(atlas));

        // TODO refactor to a fn in GasCalculatorDeployer
        // if (chainId == 42_161 || chainId == 42_170 || chainId == 421_614) {
        //     // Deploy gas calculator for Arbitrum chains
        //     console.log("Deploying L2 Gas Calculator at: ", l2GasCalculatorAddr);
        //     DeployGasCalculatorScript gasCalculatorDeployer = new DeployGasCalculatorScript();
        //     l2GasCalculatorAddr = gasCalculatorDeployer.deployL2GasCalculator();
        // }

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
        // Check FactoryLib address set correctly in Atlas
        if (address(factoryLib) != atlas.FACTORY_LIB()) {
            console.log("ERROR: FactoryLib address not set correctly in Atlas");
            error = true;
        }
        // Check ExecutionEnvironment address set correctly in FactoryLib
        if (address(execEnvTemplate) != factoryLib.EXECUTION_ENV_TEMPLATE()) {
            console.log("ERROR: ExecutionEnvironment address not set correctly in FactoryLib");
            error = true;
        }
        // Check GasCalculator address set correctly in Atlas
        if (l2GasCalculatorAddr != atlas.L2_GAS_CALCULATOR()) {
            console.log("ERROR: L2 Gas Calculator address not set correctly in Atlas");
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
        if (l2GasCalculatorAddr != address(0)) {
            _writeAddressToDeploymentsJson("L2_GAS_CALCULATOR", l2GasCalculatorAddr);
        }

        // Print the table header
        console.log("\n");
        console.log("------------------------------------------------------------------------");
        console.log("| Contract              | Address                                      |");
        console.log("------------------------------------------------------------------------");
        console.log("| Atlas                 | ", address(atlas), " |");
        console.log("| AtlasVerification     | ", address(atlasVerification), " |");
        console.log("| Simulator             | ", address(simulator), " |");
        console.log("| Sorter                | ", address(sorter), " |");
        if (l2GasCalculatorAddr != address(0)) {
            console.log("| L2 Gas Calculator     | ", l2GasCalculatorAddr, " |");
        }
        console.log("------------------------------------------------------------------------");
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
