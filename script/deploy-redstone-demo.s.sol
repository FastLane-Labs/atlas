// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { RedstoneDAppControl } from "src/contracts/examples/redstone-oev/RedstoneDAppControl.sol";
import { RedstoneAdapterAtlasWrapper } from "src/contracts/examples/redstone-oev/RedstoneAdapterAtlasWrapper.sol";
import { MockBaseFeed} from "src/contracts/examples/redstone-oev/MockBaseFeed.sol";
import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { HoneyPot } from "src/contracts/examples/redstone-oev/HoneyPot.sol";

contract DeployRedstoneDemoScript is DeployBaseScript {
    RedstoneDAppControl redstoneDAppControl;
    address redstoneExecutionEnv;
    address redstoneAdapterAtlasWrapper;

    function run() external {
        console.log("\n=== DEPLOYING REDSTONE DEMO ===\n");

        uint256 govPrivateKey = vm.envUint("DAPP_GOV_PRIVATE_KEY");
        address gov = vm.addr(govPrivateKey);

        console.log("Redstone Gov address: \t\t\t", gov);

        uint256 oracleOwnerPrivateKey = vm.envUint("ORACLE_OWNER_PRIVATE_KEY");
        address oracleOwner = vm.addr(oracleOwnerPrivateKey);
        address baseFeedAddress = vm.envAddress("BASE_FEED_ADDRESS");

        atlas = Atlas(payable(vm.envAddress("ATLAS_ADDRESS")));
        atlasVerification = AtlasVerification(payable(vm.envAddress("ATLAS_VERIFICATION_ADDRESS")));

        console.log("Using Atlas deployed at: \t\t\t", address(atlas));
        console.log("Using AtlasVerification deployed at: \t\t", address(atlasVerification));
        console.log("\n");

        vm.startBroadcast(govPrivateKey);
        console.log("Deploying from Gov Account...");

        redstoneDAppControl = new RedstoneDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(redstoneDAppControl));

        vm.stopBroadcast();
        console.log("Contracts deployed by Gov:");
        console.log("Redstone DAppControl: \t\t\t", address(redstoneDAppControl));
        console.log("\n");

        console.log("Oracle Owner address: \t\t\t", oracleOwner);
        console.log("Base Feed address: \t\t\t\t", baseFeedAddress);

        vm.startBroadcast(oracleOwnerPrivateKey);
        console.log("Deploying from Oracle Owner Account...");
        redstoneAdapterAtlasWrapper = redstoneDAppControl.createNewAtlasAdapter(baseFeedAddress);
        vm.stopBroadcast();

        console.log("Contracts deployed by Oracle Owner:");
        console.log("Redstone Adapter Atlas Wrapper: \t\t\t", redstoneAdapterAtlasWrapper);
        console.log("\n");
    }
}

contract DeployRedstoneHoneyPot is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING REDSTONE HONEY POT ===\n");

        uint256 honeyPotPrivateKey = vm.envUint("HONEYPOT_OWNER_PRIVATE_KEY");
        address honeyPotOwner = vm.addr(honeyPotPrivateKey);

        address oracle = vm.envAddress("ORACLE_ADDRESS");

        console.log("Honey Pot Owner address: \t\t", honeyPotOwner);
        console.log("Oracle address: \t\t\t", oracle);

        vm.startBroadcast(honeyPotPrivateKey);
        console.log("Deploying from Honey Pot Owner Account...");

        HoneyPot honeyPot = new HoneyPot(honeyPotOwner, oracle);

        vm.stopBroadcast();
        console.log("Contracts deployed by Honey Pot Owner:");
        console.log("Honey Pot: \t\t\t\t", address(honeyPot));
        console.log("\n");
    }
}

contract DeployRedstoneMockBaseFeed is DeployBaseScript {
    function run() external {
        console.log("\n=== DEPLOYING REDSTONE MOCK BASE FEED ===\n");

        uint256 authorizedSignerPrivateKey = vm.envUint("BASE_FEED_OWNER");
        address authorizedSigner = vm.addr(authorizedSignerPrivateKey);

        console.log("Authorized Signer address: \t\t", authorizedSigner);

        vm.startBroadcast(authorizedSignerPrivateKey);
        console.log("Deploying from Authorized Signer Account...");
        MockBaseFeed mockBaseFeed = new MockBaseFeed(authorizedSigner);
        vm.stopBroadcast();

        console.log("Contracts deployed by Authorized Signer:");
        console.log("Mock Base Feed: \t\t\t", address(mockBaseFeed));
    }
}
