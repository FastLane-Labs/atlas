// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "./base/deploy-base.s.sol";
import { ChainConfig } from "../src/contracts/libraries/ChainConfig.sol";

import { FactoryLib } from "../src/contracts/atlas/FactoryLib.sol";
import { Atlas } from "../src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";
import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";
import { Simulator } from "../src/contracts/helpers/Simulator.sol";
import { Sorter } from "../src/contracts/helpers/Sorter.sol";
import { ExecutionEnvironment } from "../src/contracts/common/ExecutionEnvironment.sol";
import { BaseGasCalculator } from "../src/contracts/gasCalculator/BaseGasCalculator.sol";

contract DeployAtlasScript is DeployBaseScript {
    // OP Stack gas calculator constants
    address constant OP_STACK_GAS_PRICE_ORACLE = address(0x420000000000000000000000000000000000000F);
    int256 constant OP_STACK_CALLDATA_LENGTH_OFFSET = 0;

    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get chain-specific configuration
        ChainConfig.ChainParameters memory chainParams = _getChainConfig();

        // Track if we need to deploy L2 gas calculator
        bool deployL2GasCalculator = false;
        uint256 nonceOffset = 0;

        // Check if L2 gas calculator is required but not configured
        if (ChainConfig.requiresL2GasCalculator(block.chainid) && chainParams.l2GasCalculator == address(0)) {
            console.log("L2 gas calculator required but not configured, will deploy automatically...");
            deployL2GasCalculator = true;
            // Calculate its future address
            address expectedL2GasCalculatorAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer));
            chainParams.l2GasCalculator = expectedL2GasCalculatorAddr;
            nonceOffset = 1; // Account for the L2 gas calculator deployment
        }

        // Computes the addresses at which AtlasVerification will be deployed
        address expectedAtlasAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + nonceOffset + 2);
        address expectedAtlasVerificationAddr =
            vm.computeCreateAddress(deployer, vm.getNonce(deployer) + nonceOffset + 3);
        address expectedSimulatorAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + nonceOffset + 4);

        address prevAtlasAddr = _getAddressFromDeploymentsJson("ATLAS");
        uint256 prevSurcharge = (prevAtlasAddr == address(0)) ? 0 : Atlas(payable(prevAtlasAddr)).cumulativeSurcharge();
        address prevSimAddr = _getAddressFromDeploymentsJson("SIMULATOR");
        uint256 prevSimBalance = (prevSimAddr == address(0)) ? 0 : prevSimAddr.balance;

        console.log("Deployer address: \t\t", deployer);
        console.log("Prev Simulator balance: \t", prevSimBalance);
        console.log("Prev Atlas Gas Surcharge: \t", prevSurcharge);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy L2 gas calculator if needed
        if (deployL2GasCalculator) {
            BaseGasCalculator gasCalculator = new BaseGasCalculator({
                gasPriceOracle: OP_STACK_GAS_PRICE_ORACLE,
                calldataLenOffset: OP_STACK_CALLDATA_LENGTH_OFFSET
            });
            console.log("L2 Gas Calculator deployed at: ", address(gasCalculator));

            // Verify the address matches our expectation
            require(address(gasCalculator) == chainParams.l2GasCalculator, "L2 gas calculator address mismatch");
        }

        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment(expectedAtlasAddr);

        // Deploy FactoryLib using precompile from Atlas v1.3 - avoids adjusting Mimic assembly
        FactoryLib factoryLib = FactoryLib(
            deployCode("src/contracts/precompiles/FactoryLib.sol/FactoryLib.json", abi.encode(address(execEnvTemplate)))
        );

        atlas = new Atlas({
            escrowDuration: chainParams.escrowDuration,
            atlasSurchargeRate: chainParams.atlasSurchargeRate,
            verification: expectedAtlasVerificationAddr,
            simulator: expectedSimulatorAddr,
            factoryLib: address(factoryLib),
            initialSurchargeRecipient: deployer,
            l2GasCalculator: chainParams.l2GasCalculator
        });
        atlasVerification =
            new AtlasVerification({ atlas: expectedAtlasAddr, l2GasCalculator: chainParams.l2GasCalculator });

        simulator = new Simulator();
        simulator.setAtlas(address(atlas));

        // If prev Atlas deployment has surcharge, withdraw it
        if (prevAtlasAddr != address(0) && prevSurcharge > 0) {
            Atlas(payable(prevAtlasAddr)).withdrawSurcharge();
        }

        // If prev Simulator deployment has native assets, withdraw them to new Simulator
        if (prevSimBalance > 0) {
            Simulator(payable(prevSimAddr)).withdrawETH(address(simulator));
        }

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
        // Check ESCROW_DURATION was not set to 0
        if (atlas.ESCROW_DURATION() == 0) {
            console.log("ERROR: ESCROW_DURATION was set to 0");
            error = true;
        }
        // Check if L2GasCalculator is set to same addr in all deployed contracts
        if (chainParams.l2GasCalculator != atlas.L2_GAS_CALCULATOR()) {
            console.log("ERROR: L2_GAS_CALCULATOR address not set correctly in Atlas");
            error = true;
        }
        if (chainParams.l2GasCalculator != atlasVerification.L2_GAS_CALCULATOR()) {
            console.log("ERROR: L2_GAS_CALCULATOR address not set correctly in AtlasVerification");
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

        // Save L2 gas calculator address if we deployed it
        if (deployL2GasCalculator) {
            _writeAddressToDeploymentsJson("L2_GAS_CALCULATOR", chainParams.l2GasCalculator);
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
        console.log("| L2GasCalculator       | ", address(chainParams.l2GasCalculator), " |");
        console.log("------------------------------------------------------------------------");
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
