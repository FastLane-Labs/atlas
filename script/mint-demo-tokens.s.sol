// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";
import { Token } from "src/contracts/helpers/DemoToken.sol";

contract MintDemoTokensScript is DeployBaseScript {
    Token dai = Token(0x930a6Cd9dbce1Bdb760DabD9cF675403ac0e0450);
    Token usda = Token(0x6aC973861427E9965eec03e7Da3D2a821f3Fd900);
    Token usdb = Token(0xC2e10FDe2158e76d56fbbB314f37824ED9398908);
    Token weth = Token(0x5419De9E37659Dec6F1CAAE245bcddADcbf3d087);

    // TODO update these 2 vars:
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
