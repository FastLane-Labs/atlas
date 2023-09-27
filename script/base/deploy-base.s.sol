// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

// NOTE: When handling JSON with StdJson, prefix keys with '.' e.g. '.ATLAS'

contract DeployBaseScript is Script {
    using stdJson for string;

    function _getAddressFromDeploymentsJson(string memory key) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);

        // console.log("Getting", key, "from deployments.json");

        return json.readAddress(key);
    }

    function _writeAddressToDeploymentsJson(string memory key, address addr) internal {
        // string memory root = vm.projectRoot();
        // string memory path = string.concat(root, "/deployments.json");
        // string memory json = vm.readFile(path);

        // // console.log("Writing", key, "to deployments.json");

        // json = json.writeAddress(key, addr);

        // vm.writeFile(path, json);
    }

}