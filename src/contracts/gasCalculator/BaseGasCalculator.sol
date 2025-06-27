//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IL2GasCalculator } from "src/contracts/interfaces/IL2GasCalculator.sol";

/// @notice Implementation:
/// https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/L2/GasPriceOracle.sol
/// @notice Deployment on Base: https://basescan.org/address/0x420000000000000000000000000000000000000f
interface IGasPriceOracle {
    function getL1FeeUpperBound(uint256 _unsignedTxSize) external view returns (uint256);
}

contract BaseGasCalculator is IL2GasCalculator, Ownable {
    uint256 internal constant _GAS_PER_CALLDATA_BYTE = 8;
    uint256 internal constant _BASE_TX_GAS_USED = 21_000;

    address public immutable GAS_PRICE_ORACLE;
    int256 public calldataLengthOffset;

    constructor(address gasPriceOracle, int256 calldataLenOffset) Ownable(msg.sender) {
        GAS_PRICE_ORACLE = gasPriceOracle;
        calldataLengthOffset = calldataLenOffset;
    }

    /// @notice Calculate the calldata cost in gas units on a L2 with a different fee structure than mainnet
    /// @param calldataLength The length of the calldata in bytes
    /// @return calldataGas The gas of the calldata in ETH
    function getCalldataGas(uint256 calldataLength) external view override returns (uint256 calldataGas) {
        // `getL1FeeUpperBound` returns the upper bound of the L1 fee in wei. It expects an unsigned transaction size in
        // bytes, *not calldata length only*, which makes this function a rough estimate.

        // Base execution gas.
        calldataGas = calldataLength * _GAS_PER_CALLDATA_BYTE;

        // L1 data cost.
        // `getL1FeeUpperBound` adds 68 to the size because it expects an unsigned transaction size.
        // Remove 68 to the length to account for this.
        if (calldataLength < 68) {
            calldataLength = 0;
        } else {
            calldataLength -= 68;
        }

        int256 _calldataLenOffset = calldataLengthOffset;

        if (_calldataLenOffset < 0 && calldataLength < uint256(-_calldataLenOffset)) {
            return calldataGas;
        }

        calldataLength += uint256(_calldataLenOffset);

        // GasPriceOracle returns the upper bound of the L1 fee in wei, so we divide by the gas price to get the gas.
        uint256 extraGas = IGasPriceOracle(GAS_PRICE_ORACLE).getL1FeeUpperBound(calldataLength) / tx.gasprice;
        calldataGas += extraGas;
    }

    /// @notice Gets the cost of initial gas used for a transaction with a different calldata fee than mainnet
    /// @param calldataLength The length of the calldata in bytes
    function initialGasUsed(uint256 calldataLength) external pure override returns (uint256 gasUsed) {
        return calldataLength * _GAS_PER_CALLDATA_BYTE;
    }

    /// @notice Sets the calldata length offset
    /// @param calldataLenOffset The new calldata length offset
    function setCalldataLengthOffset(int256 calldataLenOffset) external onlyOwner {
        calldataLengthOffset = calldataLenOffset;
    }
}
