// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { ArbitrumGasCalculator } from "src/contracts/gasCalculator/ArbitrumGasCalculator.sol";
import { BaseGasCalculator } from "src/contracts/gasCalculator/BaseGasCalculator.sol";

contract GasCalculatorDeployHelper {
    function _newGasCalculator() internal returns (address) {
        // TODO
        return address(0);
    }

    function _predictGasCalculatorAddress(address deployer, uint256 deployNonce) internal returns (address) {
        // TODO
        return address(0);
    }
}

contract DeployGasCalculatorScript is GasCalculatorDeployHelper, DeployBaseScript {
    // TODO this should also move to helper contract that creates new contract
    // NOTE: Adjust the constructor parameters as needed here:
    // -----------------------------------------------------------------------------------------------
    // Base:
    // -----------------------------------------------------------------------------------------------
    address constant BASE_GAS_PRICE_ORACLE = address(0x420000000000000000000000000000000000000F);
    int256 constant BASE_CALLDATA_LENGTH_OFFSET = 0; // can be negative or positive
    // -----------------------------------------------------------------------------------------------
    // Arbitrum:
    // -----------------------------------------------------------------------------------------------
    int256 constant ARBITRUM_CALLDATA_LENGTH_OFFSET = 0;
    // -----------------------------------------------------------------------------------------------

    function run() external {
        console.log("\n=== DEPLOYING Gas Calculator ===\n");
        console.log("Deploying to chain: \t\t", _getDeployChain());

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);
        address l2GasCalculatorAddr = _newGasCalculator();
        vm.stopBroadcast();

        _writeAddressToDeploymentsJson("L2_GAS_CALCULATOR", l2GasCalculatorAddr);

        console.log("\n");
        console.log("-------------------------------------------------------------------------------");
        console.log("| Contract                    | Address                                       |");
        console.log("-------------------------------------------------------------------------------");
        console.log("| L2_GAS_CALCULATOR           | ", l2GasCalculatorAddr, "  |");
        console.log("-------------------------------------------------------------------------------");
        console.log("\n");
        console.log("You can find the contract address in deployments.json");
    }
}

// For deploy helper
// if (chainId == 8453 || chainId == 84_532) {
//             // Base or Base Sepolia
//             BaseGasCalculator gasCalculator = new BaseGasCalculator({
//                 gasPriceOracle: BASE_GAS_PRICE_ORACLE,
//                 calldataLenOffset: BASE_CALLDATA_LENGTH_OFFSET
//             });
//             deploymentAddr = address(gasCalculator);
//         } else {
//             revert("Error: Chain ID not supported");
//         }

// function deployL2GasCalculator() public returns (address) {
//         uint256 chainId = block.chainid;
//         address deploymentAddr;

//         if (chainId == 42_161 || chainId == 421_614) {
//             // Arbitrum One or Arbitrum Sepolia
//             ArbitrumGasCalculator gasCalculator = new ArbitrumGasCalculator({
//                 calldataLenOffset: ARBITRUM_CALLDATA_LENGTH_OFFSET,
//                 _isArbitrumNova: false
//             });
//             deploymentAddr = address(gasCalculator);
//         } else if (chainId == 42_170) {
//             // Arbitrum Nova
//             ArbitrumGasCalculator gasCalculator =
//                 new ArbitrumGasCalculator({ calldataLenOffset: ARBITRUM_CALLDATA_LENGTH_OFFSET, _isArbitrumNova: true
// });
//             deploymentAddr = address(gasCalculator);
//         } else {
//             revert("Error: Chain ID not supported for gas calculator deployment");
//         }

//         return deploymentAddr;
