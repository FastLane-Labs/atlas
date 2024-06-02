//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

// NOTE: Constants that are defined but not used in the logic of a smart contract, will not be included in the bytecode
// of the smart contract when compiled.
contract AtlasConstants {
    // Atlas Constants
    // TODO refactor constants to this file if we like this pattern

    // AtlasVerification Constants
    uint8 internal constant _MAX_SOLVERS = type(uint8).max - _CALL_COUNT_EXCL_SOLVER_CALLS;

    // Shared Constants
    uint8 internal constant _CALL_COUNT_EXCL_SOLVER_CALLS = 4;
}
