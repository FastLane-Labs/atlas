// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import { DeployBaseScript } from "script/base/deploy-base.s.sol";

import { ArbitrumGasCalculator } from "src/contracts/gasCalculator/ArbitrumGasCalculator.sol";
import { BaseGasCalculator } from "src/contracts/gasCalculator/BaseGasCalculator.sol";

contract GasCalculatorDeployHelper is Test {
    // NOTE: Adjust the constructor parameters as needed here:
    // -----------------------------------------------------------------------------------------------
    // Base:
    // -----------------------------------------------------------------------------------------------
    uint256 constant BASE_SEPOLIA = 8453;
    uint256 constant BASE_MAINNET = 84_532;
    address constant BASE_GAS_PRICE_ORACLE = address(0x420000000000000000000000000000000000000F);
    int256 constant BASE_CALLDATA_LENGTH_OFFSET = 0; // can be negative or positive
    // -----------------------------------------------------------------------------------------------
    // Arbitrum:
    // -----------------------------------------------------------------------------------------------
    uint256 constant ARBITRUM_SEPOLIA = 421_614;
    uint256 constant ARBITRUM_ONE = 42_161;
    uint256 constant ARBITRUM_NOVA = 42_170;
    int256 constant ARBITRUM_CALLDATA_LENGTH_OFFSET = 0;
    // -----------------------------------------------------------------------------------------------

    function _newGasCalculator() internal returns (address l2GasCalculatorAddr) {
        uint256 chainId = block.chainid;

        if (chainId == BASE_MAINNET || chainId == BASE_SEPOLIA) {
            // Base
            BaseGasCalculator gasCalculator = new BaseGasCalculator({
                gasPriceOracle: BASE_GAS_PRICE_ORACLE,
                calldataLenOffset: BASE_CALLDATA_LENGTH_OFFSET
            });
            l2GasCalculatorAddr = address(gasCalculator);
        } else if (chainId == ARBITRUM_ONE || chainId == ARBITRUM_SEPOLIA || chainId == ARBITRUM_NOVA) {
            // Arbitrum One or Arbitrum Sepolia
            ArbitrumGasCalculator gasCalculator = new ArbitrumGasCalculator({
                calldataLenOffset: ARBITRUM_CALLDATA_LENGTH_OFFSET
            });
            l2GasCalculatorAddr = address(gasCalculator);
        } else {
            revert("Error: Chain ID not supported for L2 Gas Calculator deployment");
        }
    }

    /// @notice Returns the predicted address of the gas calculator contract, given the nonce of the deployment tx. Or
    /// returns address(0) if the current chain does not require an L2 Gas Calculator.
    function _predictGasCalculatorAddress(address deployer, uint256 deployNonce) internal returns (address) {
        if (_chainNeedsL2GasCalculator()) {
            return vm.computeCreateAddress(deployer, deployNonce);
        }

        // If not one of the supported chains above, return address(0)
        return address(0);
    }

    function _chainNeedsL2GasCalculator() internal returns (bool) {
        uint256 chainId = block.chainid;

        return (chainId == BASE_MAINNET || chainId == BASE_SEPOLIA)
            || (chainId == ARBITRUM_ONE || chainId == ARBITRUM_SEPOLIA || chainId == ARBITRUM_NOVA);
    }
}

contract DeployGasCalculatorScript is DeployBaseScript, GasCalculatorDeployHelper {
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
