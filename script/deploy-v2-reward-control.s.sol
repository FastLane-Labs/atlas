// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { V2RewardDAppControl } from "src/contracts/examples/v2-example-router/V2RewardDAppControl.sol";

contract DeployV2RewardControlScript is DeployBaseScript {
    V2RewardDAppControl v2RewardControl;

    // NOTE: Change these to the relevant addresses on the target chain if not Sepolia.
    address public constant UNISWAP_V2_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008; // on Sepolia
    // NOTE: Reward token must be the bidToken in the DAppControl. So it should be very accessible to solvers on the
    // target chain.
    // TODO check this is the latest WETH address when deploying
    address public constant REWARD_TOKEN = 0xe015b7B255438ff0Fe57B46594549A87e4915235; // Our custom WETH on Sepolia

    function run() external {
        console.log("\n=== DEPLOYING V2Reward DAppControl ===\n");
        console.log("And setting up with initializeGovernance\n");

        uint256 deployerPrivateKey = vm.envUint("DAPP_GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // atlas = Atlas(payable(_getAddressFromDeploymentsJson("ATLAS")));
        atlas = Atlas(payable(0xa892eb9F79E0D1b6277B3456b0a8FE770386f6DB));
        // atlasVerification = AtlasVerification(payable(_getAddressFromDeploymentsJson("ATLAS_VERIFICATION")));
        atlasVerification = AtlasVerification(payable(0xeeB91b2d317e3A747E88c1CA542ae31E32B87FDF));

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the DAppControl contract
        v2RewardControl = new V2RewardDAppControl(address(atlas), REWARD_TOKEN, UNISWAP_V2_ROUTER);

        // Integrate SwapIntent with Atlas
        atlasVerification.initializeGovernance(address(v2RewardControl));

        vm.stopBroadcast();

        _writeAddressToDeploymentsJson("V2_REWARD_DAPP_CONTROL", address(v2RewardControl));

        console.log("\n");
        console.log("V2Reward DAppControl deployed at: \t\t", address(v2RewardControl));
        console.log("\n");
        console.log("You can find a list of contract addresses from the latest deployment in deployments.json");
    }
}
