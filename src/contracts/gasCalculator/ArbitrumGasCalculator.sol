// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { LibBit } from "solady/utils/LibBit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ArbGasInfo } from "nitro-contracts/src/precompiles/ArbGasInfo.sol";
import { IL2GasCalculator } from "src/contracts/interfaces/IL2GasCalculator.sol";

// TODO in GasAccLib - need a way to get calldata price for static SolverOp.
// For now that can be a constant amount of zero and non-zero bytes, that get put through getCalldataGas() to get a
// number to add to solverOp.data cost.

// NOTE: For Arbitrum gas pricing calibration. Replace with constants once calibrated.
// - getCalldataGas: Y = A(zero bytes)(gasPerL1Byte) + B(non-zero bytes)(gasPerL1Byte) + C
// - initialGasUsed: Y = A(zero bytes)(gasPerL1Byte) + B(non-zero bytes)(gasPerL1Byte) + R(perL2TxInArbGas) + C
struct CalibrationVars {
    uint64 A; // zero byte calldata sensitivity to gasPerL1Byte
    uint64 B; // non-zero byte calldata sensitivity to gasPerL1Byte
    uint64 R; // initialGasUsed sensitivity to perL2TxInArbGas
    uint64 C; // constant offset
}

/// @title ArbitrumGasCalculator
/// @notice Calculates gas costs for transactions on Arbitrum
contract ArbitrumGasCalculator is IL2GasCalculator, Ownable {
    using LibBit for bytes;

    // Interface to interact with Arbitrum's gas info precompile
    ArbGasInfo public constant ARB_GAS_INFO = ArbGasInfo(address(0x000000000000000000000000000000000000006C));

    // Denominator for M in calldata gas calibration
    uint64 public constant SCALE = 10_000; // 10_000 / 10_000 = 100%

    CalibrationVars internal s_gasVars = CalibrationVars({
        A: 200, // calldata starts as 2% of perL1TxInArbGas per zero byte
        B: 9600, // calldata starts as 96% of perL1TxInArbGas per non-zero byte
        R: SCALE, // initialGasUsed starts as +100% of perL2TxInArbGas
        C: 0 // constant offset starts as 0
     });

    /// @notice Constructor
    constructor() Ownable(msg.sender) { }

    // ------------------------------------------------------- //
    //                      OWNER FUNCTIONS                    //
    // ------------------------------------------------------- //

    function getCalibrationVars() external view returns (uint64 A, uint64 B, uint64 R, uint64 C) {
        // Return the current calibration variables
        return (s_gasVars.A, s_gasVars.B, s_gasVars.R, s_gasVars.C);
    }

    function setCalibrationVars(uint64 A, uint64 B, uint64 R, uint64 C) external onlyOwner {
        // Set the calibration variables for gas calculation
        s_gasVars = CalibrationVars({ A: A, B: B, R: R, C: C });
    }

    // ------------------------------------------------------- //
    //                    EXTERNAL FUNCTIONS                   //
    // ------------------------------------------------------- //

    /// @notice Calculate the calldata cost in gas units on Arbitrum
    /// @param data The calldata for which to calculate the gas cost
    /// @return calldataGas The gas cost of the calldata in ArbGas
    function getCalldataGas(bytes calldata data) external view override returns (uint256 calldataGas) {
        // Get the number of zero and non-zero bytes in the calldata
        uint256 zeroByteCount = data.countZeroBytesCalldata();
        uint256 nonZeroByteCount = data.length - zeroByteCount;

        // Get constant perL2Tx cost, and perL1CalldataByte cost in ArbGas
        (uint256 perL2TxInArbGas, uint256 perL1CalldataByteInArbGas,) = ARB_GAS_INFO.getPricesInArbGas();
        CalibrationVars memory gasVars = s_gasVars; // Load coefficients from storage

        // Y = A(zero bytes)(gasPerL1Byte) + B(non-zero bytes)(gasPerL1Byte) + C
        calldataGas = (zeroByteCount * perL1CalldataByteInArbGas * gasVars.A / SCALE)
            + (nonZeroByteCount * perL1CalldataByteInArbGas * gasVars.B / SCALE) + gasVars.C;
    }

    /// @notice Calculate the initial gas used for a transaction
    /// @param data The calldata for which to calculate the gas cost
    /// @return gasUsed The initial gas used for the metacall in ArbGas units
    function initialGasUsed(bytes calldata data) external view override returns (uint256 gasUsed) {
        // Get the number of zero and non-zero bytes in the calldata
        uint256 zeroByteCount = data.countZeroBytesCalldata();
        uint256 nonZeroByteCount = data.length - zeroByteCount;

        // Get constant perL2Tx cost, and perL1CalldataByte cost in ArbGas
        (uint256 perL2TxInArbGas, uint256 perL1CalldataByteInArbGas,) = ARB_GAS_INFO.getPricesInArbGas();
        CalibrationVars memory gasVars = s_gasVars; // Load coefficients from storage

        // Y = A(zero bytes)(gasPerL1Byte) + B(non-zero bytes)(gasPerL1Byte) + R(perL2TxInArbGas) + C
        gasUsed = (zeroByteCount * perL1CalldataByteInArbGas * gasVars.A / SCALE)
            + (nonZeroByteCount * perL1CalldataByteInArbGas * gasVars.B / SCALE) + (perL2TxInArbGas * gasVars.R / SCALE)
            + gasVars.C;
    }
}
