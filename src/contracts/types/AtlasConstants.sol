//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./ValidCalls.sol";

import { GasAccLib } from "../libraries/GasAccLib.sol";

// NOTE: Internal constants that are defined but not used in the logic of a smart contract, will NOT be included in the
// bytecode of the smart contract when compiled. However, public constants will be included in every inheriting contract
// as they are part of the ABI. As such, only internal constants are defined in this shared contract.

contract AtlasConstants {
    // ------------------------------------------------------- //
    //                      ATLAS CONSTANTS                    //
    // ------------------------------------------------------- //

    // Atlas constants
    uint256 internal constant _GAS_VALUE_DECIMALS_TO_DROP = 1e9; // measured in gwei
    uint256 internal constant _UNLOCKED = 0;

    // Atlas constants used in `_bidFindingIteration()`
    uint256 internal constant _BITS_FOR_INDEX = 16;
    uint256 internal constant _FIRST_16_BITS_TRUE_MASK = uint256(0xFFFF);

    // Escrow constants
    uint256 internal constant _VALIDATION_GAS_LIMIT = 500_000;
    uint256 internal constant _GRACEFUL_RETURN_GAS_OFFSET = 40_000;

    // Gas Accounting constants
    uint256 internal constant _CALLDATA_LENGTH_PREMIUM_HALVED = GasAccLib._CALLDATA_LENGTH_PREMIUM_HALVED;
    // Half of the upper gas cost per byte of calldata (16 gas). Multiplied by msg.data.length. Equivalent to
    // `msg.data.length / 2 * 16` because 2 hex chars per byte.
    uint256 internal constant _BASE_TX_GAS_USED = 21_000;
    uint256 internal constant _SOLVER_OP_BASE_CALLDATA = GasAccLib._SOLVER_OP_BASE_CALLDATA; // SolverOperation calldata
        // length excluding solverOp.data
    uint256 internal constant _BUNDLER_FAULT_OFFSET = 4500; // Extra gas to write off if solverOp failure is bundler
        // fault in `_handleSolverFailAccounting()`. Value is worst-case gas measured for bundler fault.
    uint256 internal constant _SOLVER_FAULT_OFFSET = 28_800; // Extra gas to charge solver if solverOp failure is solver
        // fault in `_handleSolverFailAccounting()`. Value is worst-case gas measured for solver fault.
    uint256 internal constant _EXTRA_CALLDATA_LENGTH = 238; // incl. gasRefundBeneficiary address and dynamic offset
        // calldata

    // First 160 bits of _solverLock are the address of the current solver.
    // The 161st bit represents whether the solver has called back via `reconcile`.
    // The 162nd bit represents whether the solver's outstanding debt has been repaid via `reconcile`.
    uint256 internal constant _SOLVER_CALLED_BACK_MASK = 1 << 161;
    uint256 internal constant _SOLVER_FULFILLED_MASK = 1 << 162;

    // Used to set Lock phase without changing the activeEnvironment or callConfig.
    uint256 internal constant _LOCK_PHASE_MASK =
        uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00);

    // ValidCalls error threshold before which the metacall reverts, and after which it returns gracefully to store
    // nonces as used.
    uint8 internal constant _GRACEFUL_RETURN_THRESHOLD = uint8(ValidCallsResult.InvertBidValueCannotBeExPostBids) + 1;

    // ------------------------------------------------------- //
    //               ATLAS VERIFICATION CONSTANTS              //
    // ------------------------------------------------------- //

    uint8 internal constant _MAX_SOLVERS = type(uint8).max - 1;
    uint256 internal constant _BID_FIND_OVERHEAD = 5000; // Overhead gas for the logic required to execute and sort each
        // solverOp in `_bidFindingIteration()`

    // Params below are used to calculate the tolerated max diff between actual gasleft and expected gasleft, in the
    // `_getAndVerifyGasLimits()` function. This tolerance is mostly for calldata gas cost differences.
    uint256 internal constant _UPPER_BASE_EXEC_GAS_TOLERANCE = 20_000;
    uint256 internal constant _LOWER_BASE_EXEC_GAS_TOLERANCE = 60_000;
    uint256 internal constant _TOLERANCE_PER_SOLVER = 33_000;
}
