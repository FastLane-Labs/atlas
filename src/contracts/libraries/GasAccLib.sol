//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AccountingMath } from "./AccountingMath.sol";
import { IL2GasCalculator } from "../interfaces/IL2GasCalculator.sol";
import { SolverOperation } from "../types/SolverOperation.sol";

// All GasLedger vars are measured in units of gas.
// All GasLedger vars also include calldata and execution gas components.
// remainingMaxGas and unreachedSolverGas measure max gas limits (C + E).
// writeoffsGas and solverFaultFailureGas measure actual gas used (C + E).
// Only stores base gas values. Does not include the surcharges or gasprice components.
// type(uint48).max ~= 2.8 x 10^14, plenty even for gigagas (10^9) blocks
struct GasLedger {
    uint48 remainingMaxGas; // Measured at start, decreased by solverOp gas limits when reached
    uint48 writeoffsGas; // Gas used for solverOps but written off due to bundler fault
    uint48 solverFaultFailureGas; // Gas used by solverOps that failed due to solver fault
    uint48 unreachedSolverGas; // Sum of gas limits of solverOps not yet reached in the current metacall
    uint48 maxApprovedGasSpend; // Max gas units approved by current solver to be spent from their bonded atlETH
        // NOTE: 16 bits unused. Could hold totalSurchargeRate if SCALE = 10_000 (max surcharge = 6.5x then)
        // NOTE: could even do 6 accounts x 40 bits each, + 16 bits for total surcharge rate
}

// All BorrowsLedger vars are measured in units of native token (wei).
struct BorrowsLedger {
    uint128 borrows; // Total native token value borrowed in the current metacall
    uint128 repays; // Total native token value repaid in the current metacall
}

library GasAccLib {
    using AccountingMath for uint256;

    // TODO refactor AtlasConstants to a lib and import here
    uint256 internal constant _SOLVER_OP_BASE_CALLDATA = 608;
    uint256 internal constant _CALLDATA_LENGTH_PREMIUM_HALVED = 8;

    function pack(GasLedger memory gasLedger) internal pure returns (uint256) {
        return uint256(gasLedger.remainingMaxGas) | (uint256(gasLedger.writeoffsGas) << 48)
            | (uint256(gasLedger.solverFaultFailureGas) << 96) | (uint256(gasLedger.unreachedSolverGas) << 144)
            | (uint256(gasLedger.maxApprovedGasSpend) << 192);
    }

    function pack(BorrowsLedger memory borrowsLedger) internal pure returns (uint256) {
        return uint256(borrowsLedger.borrows) | (uint256(borrowsLedger.repays) << 128);
    }

    function toGasLedger(uint256 gasLedgerPacked) internal pure returns (GasLedger memory) {
        return GasLedger({
            remainingMaxGas: uint48(gasLedgerPacked),
            writeoffsGas: uint48(gasLedgerPacked >> 48),
            solverFaultFailureGas: uint48(gasLedgerPacked >> 96),
            unreachedSolverGas: uint48(gasLedgerPacked >> 144),
            maxApprovedGasSpend: uint48(gasLedgerPacked >> 192)
        });
    }

    function toBorrowsLedger(uint256 borrowsLedgerPacked) internal pure returns (BorrowsLedger memory) {
        return BorrowsLedger({ borrows: uint128(borrowsLedgerPacked), repays: uint128(borrowsLedgerPacked >> 128) });
    }

    // Returns the max gas liability for the current solver.
    // `remainingMaxGas` is max gas limit as measured at start of metacall, with the gas limit of each solverOp
    // subtracted at the end of its execution.
    // `unreachedSolverGas` is the sum of solverOp gas limits not yet reached, with gas limit of current solverOp
    // subtracted at the start of its execution, before bonded balance check.
    // Thus `remainingMaxGas - unreachedSolverGas` is the max gas the current solver might need to pay for if they win,
    // including dApp hook gas limits and userOp gas limit.
    function solverGasLiability(GasLedger memory gL, uint256 totalSurchargeRate) internal pure returns (uint256) {
        return uint256(gL.remainingMaxGas - gL.unreachedSolverGas).withSurcharge(totalSurchargeRate);
    }

    function solverOpCalldataGas(
        uint256 calldataLength,
        address l2GasCalculator
    )
        internal
        view
        returns (uint256 calldataGas)
    {
        if (l2GasCalculator == address(0)) {
            // Default to using mainnet gas calculations
            // _SOLVER_OP_BASE_CALLDATA = SolverOperation calldata length excluding solverOp.data
            calldataGas = (calldataLength + _SOLVER_OP_BASE_CALLDATA) * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            calldataGas = IL2GasCalculator(l2GasCalculator).getCalldataGas(calldataLength + _SOLVER_OP_BASE_CALLDATA);
        }
    }

    function sumSolverOpsCalldataGas(
        SolverOperation[] calldata solverOps,
        address l2GasCalculator
    )
        internal
        view
        returns (uint256 sumCalldataGas)
    {
        uint256 solverOpsLength = solverOps.length;
        uint256 sumDataLengths;

        if (solverOpsLength == 0) return 0;

        for (uint256 i = 0; i < solverOpsLength; ++i) {
            sumDataLengths += solverOps[i].data.length;
        }

        uint256 sumSolverOpsCalldata = solverOpsLength * _SOLVER_OP_BASE_CALLDATA + sumDataLengths;

        if (l2GasCalculator == address(0)) {
            sumCalldataGas = sumSolverOpsCalldata * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            sumCalldataGas = IL2GasCalculator(l2GasCalculator).getCalldataGas(sumSolverOpsCalldata);
        }
    }

    function metacallCalldataGas(
        uint256 msgDataLength,
        address l2GasCalculator
    )
        internal
        view
        returns (uint256 calldataGas)
    {
        if (l2GasCalculator == address(0)) {
            calldataGas = msgDataLength * _CALLDATA_LENGTH_PREMIUM_HALVED;
        } else {
            calldataGas = IL2GasCalculator(l2GasCalculator).initialGasUsed(msgDataLength);
        }
    }
}
