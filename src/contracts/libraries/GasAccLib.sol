//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

// All GasLedger vars are measured in units of gas.
// All GasLedger vars also include calldata and execution gas components.
struct GasLedger {
    uint64 totalMetacallGas; // Measured by gasMarker at start, decreased by writeoffs
    uint64 solverFaultFailureGas; // Gas used by solverOps that failed due to solver fault
    uint64 unreachedSolverGas; // Total for solverOps that have not yet been reached in the current metacall
    uint64 maxApprovedGasSpend; // Max gas units approved by current solver to be spent from their bonded atlETH
}

// All BorrowsLedger vars are measured in units of native token (wei).
struct BorrowsLedger {
    uint128 borrows; // Total native token value borrowed in the current metacall
    uint128 repays; // Total native token value repaid in the current metacall
}

library GasAccLib {
    function pack(GasLedger memory gasLedger) internal pure returns (uint256) {
        return uint256(gasLedger.totalMetacallGas) |
            (uint256(gasLedger.solverFaultFailureGas) << 64) |
            (uint256(gasLedger.unreachedSolverGas) << 128) |
            (uint256(gasLedger.maxApprovedGasSpend) << 192);
    }

    function pack(BorrowsLedger memory borrowsLedger) internal pure returns (uint256) {
        return uint256(borrowsLedger.borrows) | (uint256(borrowsLedger.repays) << 128);
    }

    function toGasLedger(uint256 packed) internal pure returns (GasLedger memory) {
        return GasLedger({
            totalMetacallGas: uint64(packed),
            solverFaultFailureGas: uint64(packed >> 64),
            unreachedSolverGas: uint64(packed >> 128),
            maxApprovedGasSpend: uint64(packed >> 192)
        });
    }

    function toBorrowsLedger(uint256 packed) internal pure returns (BorrowsLedger memory) {
        return BorrowsLedger({
            borrows: uint128(packed),
            repays: uint128(packed >> 128)
        });
    }
}
