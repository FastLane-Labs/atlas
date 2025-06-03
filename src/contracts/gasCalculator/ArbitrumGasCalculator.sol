// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ArbGasInfo } from "nitro-contracts/src/precompiles/ArbGasInfo.sol";
import { IL2GasCalculator } from "src/contracts/interfaces/IL2GasCalculator.sol";

// TODO Remove this when Arbitrum calldata gas calculation is calibrated
// Temporary struct to hold all calldata calibration variables in a single slot.
// Gas Per L2 Calldata Byte = calldataLength * perL1CalldataByte * (M / SCALE) + C
struct CalibrationVars {
    uint128 M; // Coefficient for calldata length
    uint128 C; // Constant offset
}

/// @title ArbitrumGasCalculator
/// @notice Calculates gas costs for transactions on Arbitrum
contract ArbitrumGasCalculator is IL2GasCalculator, Ownable {
    // Interface to interact with Arbitrum's gas info precompile
    ArbGasInfo public immutable ARB_GAS_INFO;

    // Denominator for M in calldata gas calibration
    uint128 public constant SCALE = 10_000; // 10_000 / 10_000 = 100%

    CalibrationVars internal s_gasVars = CalibrationVars({
        M: SCALE, // Scaling factor of 100%
        C: 0 // Offset of 0
     });

    /// @notice Constructor
    constructor() Ownable(msg.sender) {
        ARB_GAS_INFO = ArbGasInfo(address(0x000000000000000000000000000000000000006C));
    }

    function getCalibrationVars() external view returns (uint128 M, uint128 C) {
        // Return the current calibration variables
        return (s_gasVars.M, s_gasVars.C);
    }

    function setCalibrationVars(uint128 M, uint128 C) external onlyOwner {
        // Set the calibration variables for gas calculation
        s_gasVars = CalibrationVars({ M: M, C: C });
    }

    /// @notice Calculate the calldata cost in gas units on Arbitrum
    /// @param calldataLength Length of the calldata in bytes
    /// @return calldataGas The gas cost of the calldata in ArbGas
    function getCalldataGas(uint256 calldataLength) external view override returns (uint256 calldataGas) {
        // Get the price per L1 calldata byte in ArbGas
        (, uint256 perL1CalldataByte,) = ARB_GAS_INFO.getPricesInArbGas();
        return calldataLength * perL1CalldataByte * s_gasVars.M / SCALE + s_gasVars.C;
    }

    /// @notice Calculate the initial gas used for a transaction
    /// @param calldataLength Length of the calldata
    /// @return gasUsed The amount of gas used
    function initialGasUsed(uint256 calldataLength) external view override returns (uint256 gasUsed) {
        // Get the price per L1 calldata byte in ArbGas
        (, uint256 perL1CalldataByte,) = ARB_GAS_INFO.getPricesInArbGas();
        return calldataLength * perL1CalldataByte * s_gasVars.M / SCALE + s_gasVars.C;
    }
}
