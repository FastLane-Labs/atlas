// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { Token } from "src/contracts/helpers/DemoToken.sol";
import { DemoWETH } from "src/contracts/helpers/DemoWETH.sol";

contract MintDemoTokensScript is DeployBaseScript {
    // TODO update these to latest token addresses:
    Token dai = Token(0x67A779F8858175316F22843d559fFE7aa3575e95);
    Token usda = Token(0x2C10ae567104eB0665eeDE0cA783b9704ca6242A);
    Token usdb = Token(0x8A7f6437B61EB15ceA7ab1131b81585c9bFa1EA4);
    DemoWETH weth = DemoWETH(payable(0xe015b7B255438ff0Fe57B46594549A87e4915235));

    // TODO update to desired recipient and amount
    address public tokenRecipient = address(1);
    uint256 public tokenAmount = 1_000_000 ether;

    function run() external {
        console.log("\n=== MINT DEMO TOKENS ===\n");

        uint256 deployerPrivateKey = vm.envUint("DAPP_GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        dai.mint(tokenRecipient, tokenAmount);
        usda.mint(tokenRecipient, tokenAmount);
        usdb.mint(tokenRecipient, tokenAmount);
        weth.mint(tokenRecipient, tokenAmount);

        vm.stopBroadcast();

        console.log("\n");
    }
}
