// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

contract Utilities is Script {
    using stdJson for string;

    function getUsefulContractAddress(string memory chain, string memory key) public view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/useful-addresses.json");
        string memory json = vm.readFile(path);
        string memory fullKey = string.concat(".", chain, ".", key);

        address res = json.readAddress(fullKey);
        if (res == address(0x0000000000000000000000000000000000000020)) {
            revert(string.concat(fullKey, " not found in useful-addresses.json"));
        }
        return res;
    }
}
