// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { ChainlinkDAppControl } from "src/contracts/examples/oev-example/ChainlinkDAppControl.sol";
import { ChainlinkAtlasWrapper } from "src/contracts/examples/oev-example/ChainlinkAtlasWrapper.sol";

import { Token } from "src/contracts/helpers/DemoToken.sol";
import { DemoLendingProtocol } from "src/contracts/helpers/DemoLendingProtocol.sol";

contract DeployOEVDemoScript is DeployBaseScript {
    address public constant CHAINLINK_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // on Sepolia

    Token dai;
    DemoLendingProtocol lendingProtocol;
    ChainlinkDAppControl chainlinkDAppControl;
    ChainlinkAtlasWrapper lendingProtocolChainlinkWrapper;

    function run() external sphinx {
        console.log("\n=== DEPLOY OEV DEMO ===\n");

        // Your deployment is executed by a Gnosis Safe that you own. Sphinx automatically deploys
        // a Gnosis Safe at identical addresses across chains via Create2.
        address deployer = safeAddress();

        console.log("Deployer address: \t\t\t\t", deployer);

        // Deploy some contracts for demo purposes
        Atlas atlas = new Atlas(0, address(0), address(0), address(0), address(0));
        new AtlasVerification(address(atlas));
        dai = new Token("Token", "T", 18);
        lendingProtocol = new DemoLendingProtocol(address(dai));
        chainlinkDAppControl = new ChainlinkDAppControl(address(atlas));
        lendingProtocolChainlinkWrapper = new ChainlinkAtlasWrapper(address(atlas), CHAINLINK_ETH_USD, deployer);

        console.log("\n");
        console.log("Demo Lending Protocol: \t\t", address(lendingProtocol));
        console.log("Chainlink DAppControl: \t\t", address(chainlinkDAppControl));
        console.log("Protocol's Chainlink Wrapper: \t\t\t", address(lendingProtocolChainlinkWrapper));
        console.log("Real Chainlink Feed: \t\t\t", CHAINLINK_ETH_USD);
        console.log("\n");
    }

    function createLiquidatablePosition(uint256 amount, uint256 liquidationPrice) public {
        // TODO approve DAI, deposit into DemoLendingProtocol
    }
}
