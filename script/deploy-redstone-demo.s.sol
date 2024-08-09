// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { RedstoneDAppControl } from "src/contracts/examples/redstone-oev/RedstoneDAppControl.sol";
import { RedstoneAdapterAtlasWrapper } from "src/contracts/examples/redstone-oev/RedstoneAdapterAtlasWrapper.sol";
import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";

contract DeployRedstoneDemoScript is DeployBaseScript {
    RedstoneDAppControl redstoneDAppControl;
    address redstoneExecutionEnv;
    RedstoneAdapterAtlasWrapper redstoneAdapterAtlasWrapper;

    function run() external {
        console.log("\n=== DEPLOYING REDSTONE DEMO ===\n");

        uint256 govPrivateKey = vm.envUint("DAPP_GOV_PRIVATE_KEY");
        address gov = vm.addr(govPrivateKey);

        console.log("Redstone Gov address: \t\t\t", gov);

        atlas = Atlas(payable(vm.envAddress("ATLAS_ADDRESS")));
        atlasVerification = AtlasVerification(payable(vm.envAddress("ATLAS_VERIFICATION_ADDRESS")));

        console.log("Using Atlas deployed at: \t\t\t", address(atlas));
        console.log("Using AtlasVerification deployed at: \t\t", address(atlasVerification));
        console.log("\n");

        vm.startBroadcast(govPrivateKey);
        console.log("Deploying from Gov Account...");

        redstoneDAppControl = new RedstoneDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(redstoneDAppControl));

        redstoneExecutionEnv = atlas.createExecutionEnvironment(address(redstoneDAppControl));

        vm.stopBroadcast();
        console.log("Contracts deployed by Gov:");
        console.log("Redstone DAppControl: \t\t\t", address(redstoneDAppControl));
        console.log("Redstone Execution Environment: \t\t", redstoneExecutionEnv);
        console.log("\n");

        uint256 oracleOwnerPrivateKey = vm.envUint("ORACLE_OWNER_PRIVATE_KEY");
        address oracleOwner = vm.addr(oracleOwnerPrivateKey);
        address baseFeedAddress = vm.envAddress("BASE_FEED_ADDRESS");

        console.log("Oracle Owner address: \t\t\t", oracleOwner);
        console.log("Base Feed address: \t\t\t\t", baseFeedAddress);

        vm.startBroadcast(oracleOwnerPrivateKey);
        console.log("Deploying from Oracle Owner Account...");
        redstoneDAppControl.createNewAtlasAdapter(baseFeedAddress);
        vm.stopBroadcast();

        console.log("Contracts deployed by Oracle Owner:");
        console.log("Redstone Adapter Atlas Wrapper: \t\t\t", address(redstoneAdapterAtlasWrapper));
        console.log("\n");
    }
}
