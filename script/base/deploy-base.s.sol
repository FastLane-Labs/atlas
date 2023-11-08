// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

// NOTE: When handling JSON with StdJson, prefix keys with '.' e.g. '.ATLAS'

contract DeployBaseScript is Script {
    using stdJson for string;

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function _getAddressFromDeploymentsJson(string memory key) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);

        // console.log("Getting", key, "from deployments.json");

        return json.readAddress(key);
    }

    function _writeAddressToDeploymentsJson(string memory key, address addr) internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");

        // console.log(string.concat("Writing \t\t'", key), "': '", addr, "'\t\t to deployments.json");

        vm.writeJson(vm.toString(addr), path, key);
    }

    function _logTokenBalances(address account, string memory accountLabel) internal view {
        console.log("Balances for", accountLabel); 
        console.log("WETH balance: \t\t\t\t", WETH.balanceOf(account));
        console.log("DAI balance: \t\t\t\t\t", DAI.balanceOf(account));
        console.log("\n");
    }
}