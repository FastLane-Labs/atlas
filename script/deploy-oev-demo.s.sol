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

    function run() external {
        console.log("\n=== DEPLOY OEV DEMO ===\n");

        uint256 deployerPrivateKey = vm.envUint("DAPP_GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // TODO

        atlas = Atlas(payable(_getAddressFromDeploymentsJson("ATLAS")));
        // atlas = Atlas(payable(0xa892eb9F79E0D1b6277B3456b0a8FE770386f6DB)); OLD
        atlasVerification = AtlasVerification(payable(_getAddressFromDeploymentsJson("ATLAS_VERIFICATION")));
        // atlasVerification = AtlasVerification(payable(0xeeB91b2d317e3A747E88c1CA542ae31E32B87FDF));

        // Deploy token used in Demo Lending Protocol
        dai = new Token("DAI Stablecoin", "DAI", 18);

        // Deploy Demo Lending Protocol
        lendingProtocol = new DemoLendingProtocol(address(dai));

        // Deploy and initialize Chainlink DAppControl
        chainlinkDAppControl = new ChainlinkDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(chainlinkDAppControl));

        // TODO - done by DApp Gov. Need signers array still
        // Set Chainlink ETH/USD signers in DAppControl
        // chainlinkDAppControl.setSignersForBaseFeed(chainlinkETHUSD, getETHUSDSigners_Sepolia());

        // TODO - done by Chainlink Node Operator
        // vm.broadcast(chainlinkNodePrivateKey);
        // address executionEnvironment = atlas.createExecutionEnvironment(address(chainlinkDAppControl));

        // TODO come back to this

        vm.stopBroadcast();

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

    function getETHUSDSigners_Sepolia() public view returns (address[] memory) {
        address[] memory signers = new address[](4);
        signers[0] = 0xb4DC896090D778acC910db4D31f23d3667Add7Db;
        signers[1] = 0x1b178090f318c9Fd2322D52a5aC85ebBcE6Bf5E7;
        signers[2] = 0xB69dC0CaD9c739220A941f3D1C013ffd4CE7Dd6C;
        signers[3] = 0x8CACd95416d74702bccC9336Fc15F7dD0b533dDe;
        return signers;
    }
}
