//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { AccountingMath } from "./AccountingMath.sol";
import { IL2GasCalculator } from "../interfaces/IL2GasCalculator.sol";
import { SolverOperation } from "../types/SolverOperation.sol";

// All GasLedger vars are measured in units of gas.
// All GasLedger vars also include calldata and execution gas components.
// remainingMaxGas and unreachedSolverGas measure max gas limits (C + E).
// writeoffsGas and solverFaultFailureGas measure actual gas used (C + E).
// Only stores base gas values. Does not include the surcharges or gasprice components.
// type(uint40).max ~= 1.09 x 10^12, plenty even for gigagas (10^9) blocks
struct GasLedger {
    uint40 remainingMaxGas; // Measured at start, decreased by solverOp gas limits when reached
    uint40 writeoffsGas; // Gas used for solverOps but written off due to bundler fault
    uint40 solverFaultFailureGas; // Gas used by solverOps that failed due to solver fault
    uint40 unreachedSolverGas; // Sum of gas limits of solverOps not yet reached in the current metacall
    uint40 maxApprovedGasSpend; // Max gas units approved by current solver to be spent from their bonded atlETH
    uint24 atlasSurchargeRate; // Scale is 10_000 (100%) --> max atlas surcharge rate ~= 167.77x or 16777%
    uint24 bundlerSurchargeRate; // Scale is 10_000 (100%) --> max bundler surcharge rate ~= 167.77x or 16777%
        // NOTE: 8 bits unused.
}

// All BorrowsLedger vars are measured in units of native token (wei).
struct BorrowsLedger {
    uint128 borrows; // Total native token value borrowed in the current metacall
    uint128 repays; // Total native token value repaid in the current metacall
}

library GasAccLib {
    using AccountingMath for uint256;
    using SafeCast for uint256;

    uint256 internal constant _SOLVER_OP_BASE_CALLDATA = 608;
    uint256 internal constant _CALLDATA_LENGTH_PREMIUM_HALVED = 8;

    function pack(GasLedger memory gasLedger) internal pure returns (uint256) {
        return uint256(gasLedger.remainingMaxGas) | (uint256(gasLedger.writeoffsGas) << 40)
            | (uint256(gasLedger.solverFaultFailureGas) << 80) | (uint256(gasLedger.unreachedSolverGas) << 120)
            | (uint256(gasLedger.maxApprovedGasSpend) << 160) | (uint256(gasLedger.atlasSurchargeRate) << 200)
            | (uint256(gasLedger.bundlerSurchargeRate) << 224);
    }

    function pack(BorrowsLedger memory borrowsLedger) internal pure returns (uint256) {
        return uint256(borrowsLedger.borrows) | (uint256(borrowsLedger.repays) << 128);
    }

    function toGasLedger(uint256 gasLedgerPacked) internal pure returns (GasLedger memory) {
        return GasLedger({
            remainingMaxGas: uint40(gasLedgerPacked),
            writeoffsGas: uint40(gasLedgerPacked >> 40),
            solverFaultFailureGas: uint40(gasLedgerPacked >> 80),
            unreachedSolverGas: uint40(gasLedgerPacked >> 120),
            maxApprovedGasSpend: uint40(gasLedgerPacked >> 160),
            atlasSurchargeRate: uint24(gasLedgerPacked >> 200),
            bundlerSurchargeRate: uint24(gasLedgerPacked >> 224)
        });
    }

    function toBorrowsLedger(uint256 borrowsLedgerPacked) internal pure returns (BorrowsLedger memory) {
        return BorrowsLedger({ borrows: uint128(borrowsLedgerPacked), repays: uint128(borrowsLedgerPacked >> 128) });
    }

    function netRepayments(BorrowsLedger memory bL) internal pure returns (int256) {
        return uint256(bL.repays).toInt256() - uint256(bL.borrows).toInt256();
    }

    // Returns the max gas liability (in native token units) for the current solver.
    // `remainingMaxGas` is max gas limit as measured at start of metacall, with the gas limit of each solverOp
    // subtracted at the end of its execution.
    // `unreachedSolverGas` is the sum of solverOp gas limits not yet reached, with gas limit of current solverOp
    // subtracted at the start of its execution, before bonded balance check.
    // Thus `remainingMaxGas - unreachedSolverGas` is the max gas the current solver might need to pay for if they win,
    // including dApp hook gas limits and userOp gas limit.
    function solverGasLiability(GasLedger memory gL) internal view returns (uint256) {
        return uint256(gL.remainingMaxGas - gL.unreachedSolverGas).withSurcharge(
            uint256(gL.atlasSurchargeRate + gL.bundlerSurchargeRate)
        ) * tx.gasprice;
    }

    // Returns the sum of the Atlas and bundler surcharge rates.
    // Scale of the returned value is 10_000 (100%).
    function totalSurchargeRate(GasLedger memory gL) internal pure returns (uint256) {
        return uint256(gL.atlasSurchargeRate + gL.bundlerSurchargeRate);
    }

    function solverOpCalldataGas(bytes calldata data, address l2GasCalculator) internal view returns (uint256 gas) {
        if (l2GasCalculator == address(0)) {
            // Default to using mainnet gas calculations
            // _SOLVER_OP_BASE_CALLDATA = SolverOperation calldata length excluding solverOp.data
            gas = (data.length + _SOLVER_OP_BASE_CALLDATA) * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            // TODO fix the 2nd piece here - see ArbitrumGasCalculator.sol
            gas = IL2GasCalculator(l2GasCalculator).getCalldataGas(data);

            // TODO fix this: temporary hack to calc static solverOp calldata price in ArbGas
            // Takes average gas per byte and assumes static solverOp has same zero:non-zero byte ratio.
            gas += _SOLVER_OP_BASE_CALLDATA * (gas / data.length);
        }
    }

    // Same as `solverOpCalldataGas()` but takes a memory data argument, instead of calldata.
    function solverOpCalldataGasMemoryArg(
        bytes memory data,
        address l2GasCalculator
    )
        internal
        view
        returns (uint256 gas)
    {
        if (l2GasCalculator == address(0)) {
            // Default to using mainnet gas calculations
            // _SOLVER_OP_BASE_CALLDATA = SolverOperation calldata length excluding solverOp.data
            gas = (data.length + _SOLVER_OP_BASE_CALLDATA) * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            // TODO fix the 2nd piece here - see ArbitrumGasCalculator.sol
            gas = IL2GasCalculator(l2GasCalculator).getCalldataGas(data);

            // TODO fix this: temporary hack to calc static solverOp calldata price in ArbGas
            // Takes average gas per byte and assumes static solverOp has same zero:non-zero byte ratio.
            gas += _SOLVER_OP_BASE_CALLDATA * (gas / data.length);
        }
    }

    function calldataGas(bytes calldata data, address l2GasCalculator) internal view returns (uint256 gas) {
        if (l2GasCalculator == address(0)) {
            // Default to using mainnet gas calculations
            gas = data.length * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            gas = IL2GasCalculator(l2GasCalculator).getCalldataGas(data);
        }
    }

    function metacallCalldataGas(
        bytes calldata msgData,
        address l2GasCalculator
    )
        internal
        view
        returns (uint256 calldataGas)
    {
        if (l2GasCalculator == address(0)) {
            calldataGas = msgData.length * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            calldataGas = IL2GasCalculator(l2GasCalculator).initialGasUsed(msgData);
        }
    }

    function metacallCalldataGasMemoryArg(
        bytes memory msgData,
        address l2GasCalculator
    )
        internal
        view
        returns (uint256 calldataGas)
    {
        if (l2GasCalculator == address(0)) {
            calldataGas = msgData.length * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            calldataGas = IL2GasCalculator(l2GasCalculator).initialGasUsed(msgData);
        }
    }
}
