// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {Atlas} from "src/contracts/atlas/Atlas.sol";


contract DeployAtlasScript is Script {

    Atlas public atlas;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        atlas = new Atlas(64);

        console.log("Atlas deployed at: ", address(atlas));

        vm.stopBroadcast();
    }

}