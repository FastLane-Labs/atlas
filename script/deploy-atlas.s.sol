// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {DeployBaseScript} from "script/base/deploy-base.s.sol";

import {Atlas} from "src/contracts/atlas/Atlas.sol";
import {AtlasFactory} from "src/contracts/atlas/AtlasFactory.sol";
import {AtlasVerification} from "src/contracts/atlas/AtlasVerification.sol";
import {GasAccountingLib} from "src/contracts/atlas/GasAccountingLib.sol";
import {SafetyLocksLib} from "src/contracts/atlas/SafetyLocksLib.sol";
import {SwapIntentController} from "src/contracts/examples/intents-example/SwapIntent.sol";
import {TxBuilder} from "src/contracts/helpers/TxBuilder.sol";
import {Simulator} from "src/contracts/helpers/Simulator.sol";

contract DeployAtlasScript is DeployBaseScript {
    // TODO move commons vars like these to base deploy script
    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    GasAccountingLib public gasAccountingLib;
    SafetyLocksLib public safetyLocksLib;
    Simulator public simulator;

    function run() external {
        console.log("\n=== DEPLOYING Atlas ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // Computes the addresses at which AtlasFactory and AtlasVerification will be deployed
        address expectedAtlasFactoryAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 1
        );
        address expectedAtlasVerificationAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 2
        );
        address expectedGasAccountingLibAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 3
        );
        address expectedSafetyLocksLibAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 4
        );

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        simulator = new Simulator();
        atlas = new Atlas({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator)
        });
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));
        gasAccountingLib = new GasAccountingLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });
        safetyLocksLib = new SafetyLocksLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SIMULATOR", address(simulator));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
    }
}

contract DeployAtlasAndSwapIntentDAppControlScript is DeployBaseScript {
    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    GasAccountingLib public gasAccountingLib;
    SafetyLocksLib public safetyLocksLib;
    Simulator public simulator;
    SwapIntentController public swapIntentControl;

    function run() external {
        console.log("\n=== DEPLOYING Atlas and SwapIntent DAppControl ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // Computes the addresses at which AtlasFactory and AtlasVerification will be deployed
        address expectedAtlasFactoryAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 1
        );
        address expectedAtlasVerificationAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 2
        );
        address expectedGasAccountingLibAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 3
        );
        address expectedSafetyLocksLibAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 4
        );

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        simulator = new Simulator();
        atlas = new Atlas({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator)
        });
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));
        gasAccountingLib = new GasAccountingLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });
        safetyLocksLib = new SafetyLocksLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlasVerification.initializeGovernance(address(swapIntentControl));
        atlasVerification.integrateDApp(address(swapIntentControl));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SIMULATOR", address(simulator));
        _writeAddressToDeploymentsJson(".SWAP_INTENT_DAPP_CONTROL", address(swapIntentControl));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
    }
}

contract DeployAtlasAndSwapIntentDAppControlAndTxBuilderScript is DeployBaseScript {
    Atlas public atlas;
    AtlasFactory public atlasFactory;
    AtlasVerification public atlasVerification;
    GasAccountingLib public gasAccountingLib;
    SafetyLocksLib public safetyLocksLib;
    Simulator public simulator;
    SwapIntentController public swapIntentControl;
    TxBuilder public txBuilder;

    function run() external {
        console.log("\n=== DEPLOYING Atlas and SwapIntent DAppControl and TxBuilder ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // Computes the addresses at which AtlasFactory and AtlasVerification will be deployed
        address expectedAtlasFactoryAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 1
        );
        address expectedAtlasVerificationAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 2
        );
        address expectedGasAccountingLibAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 3
        );
        address expectedSafetyLocksLibAddr = computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 4
        );

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        simulator = new Simulator();
        atlas = new Atlas({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator)
        });
        atlasFactory = new AtlasFactory(address(atlas));
        atlasVerification = new AtlasVerification(address(atlas));
        gasAccountingLib = new GasAccountingLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _safetyLocksLib: expectedSafetyLocksLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });
        safetyLocksLib = new SafetyLocksLib({
            _escrowDuration: 64,
            _factory: expectedAtlasFactoryAddr,
            _verification: expectedAtlasVerificationAddr,
            _gasAccLib: expectedGasAccountingLibAddr,
            _simulator: address(simulator),
            _atlas: address(atlas)
        });

        // Deploy the SwapIntent DAppControl contract
        swapIntentControl = new SwapIntentController(address(atlas));

        // Integrate SwapIntent with Atlas
        atlasVerification.initializeGovernance(address(swapIntentControl));
        atlasVerification.integrateDApp(address(swapIntentControl));

        // Deploy the TxBuilder
        txBuilder = new TxBuilder(address(swapIntentControl), address(atlas), address(atlas));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson(".ATLAS", address(atlas));
        _writeAddressToDeploymentsJson(".SIMULATOR", address(simulator));
        _writeAddressToDeploymentsJson(".SWAP_INTENT_DAPP_CONTROL", address(swapIntentControl));
        _writeAddressToDeploymentsJson(".TX_BUILDER", address(txBuilder));

        console.log("\n");
        console.log("Atlas deployed at: \t\t\t\t", address(atlas));
        console.log("Simulator deployed at: \t\t\t", address(simulator));
        console.log("SwapIntent DAppControl deployed at: \t\t", address(swapIntentControl));
        console.log("TxBuilder deployed at: \t\t\t", address(txBuilder));
    }
}
