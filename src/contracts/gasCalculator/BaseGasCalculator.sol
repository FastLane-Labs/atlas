//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { IL2GasCalculator } from "src/contracts/interfaces/IL2GasCalculator.sol";

/// @notice Implementation:
/// https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/L2/GasPriceOracle.sol
/// @notice Deployment on Base: https://basescan.org/address/0x420000000000000000000000000000000000000f
interface IGasPriceOracle {
    function getL1FeeUpperBound(uint256 _unsignedTxSize) external view returns (uint256);
}

contract BaseGasCalculator is IL2GasCalculator {
    uint256 public constant _CALLDATA_LENGTH_PREMIUM = 32; // TODO: copied value from Atlas, should it be different for
        // Base?
    uint256 internal constant _BASE_TRANSACTION_GAS_USED = 21_000;

    address public immutable gasPriceOracle;

    constructor(address _gasPriceOracle) {
        gasPriceOracle = _gasPriceOracle;
    }

    /// @notice Calculate the cost of calldata in ETH on a L2 with a different fee structure than mainnet
    /// @param calldataLength The length of the calldata in bytes
    function getCalldataCost(uint256 calldataLength) external view override returns (uint256 calldataCost) {
        // `getL1FeeUpperBound` returns the upper bound of the L1 fee in wei. It expects an unsigned transaction size in
        // bytes, *not calldata length only*, which makes this function a rough estimate.

        // Base execution cost.
        calldataCost = calldataLength * _CALLDATA_LENGTH_PREMIUM * tx.gasprice;

        // L1 data cost.
        // `getL1FeeUpperBound` adds 68 to the size because it expects an unsigned transaction size.
        // Remove 68 to the length to account for this.
        calldataCost += IGasPriceOracle(gasPriceOracle).getL1FeeUpperBound(calldataLength - 68);
    }

    /// @notice Gets the cost of initial gas used for a transaction with a different calldata fee than mainnet
    /// @param calldataLength The length of the calldata in bytes
    function initialGasUsed(uint256 calldataLength) external pure override returns (uint256 gasUsed) {
        return _BASE_TRANSACTION_GAS_USED + (calldataLength * _CALLDATA_LENGTH_PREMIUM);
    }
}
