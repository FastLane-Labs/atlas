// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { RedstoneOevDAppControl } from "src/contracts/examples/redstone-oev/RedstoneOevDAppControl.sol";
import { RedstoneAdapterAtlasWrapper } from "src/contracts/examples/redstone-oev/RedstoneAdapterAtlasWrapper.sol";
import { MockBaseFeed } from "src/contracts/examples/redstone-oev/MockBaseFeed.sol";
import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { HoneyPot } from "src/contracts/examples/redstone-oev/HoneyPot.sol";

contract DeployRedstoneOevControlScript is DeployBaseScript {
    RedstoneOevDAppControl redstoneDAppControl;

    function run() external {
        console.log("\n=== DEPLOYING REDSTONE OEV CONTROL ===\n");

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        address atlasAddress = _getAddressFromDeploymentsJson("ATLAS");
        address atlasVerificationAddress = _getAddressFromDeploymentsJson("ATLAS_VERIFICATION");

        console.log("Using Atlas deployed at: \t\t\t", atlasAddress);
        console.log("Using Atlas Verification deployed at: \t", atlasVerificationAddress);
        console.log("\n");

        console.log("Deploying from deployer Account...");

        vm.startBroadcast(deployerPrivateKey);

        redstoneDAppControl = new RedstoneOevDAppControl(
            atlasAddress,
            0, // Bundler share
            1000, // Fastlane share (10%)
            deployer // Allocation destination
        );

        AtlasVerification(atlasVerificationAddress).initializeGovernance(address(redstoneDAppControl));

        vm.stopBroadcast();

        console.log("Contracts deployed by deployer:");
        console.log("Redstone OEV DAppControl: \t\t\t", address(redstoneDAppControl));
        console.log("\n");
    }
}
