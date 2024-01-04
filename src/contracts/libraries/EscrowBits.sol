//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/EscrowTypes.sol";

library EscrowBits {
    uint256 public constant SOLVER_GAS_LIMIT = 1_000_000;
    uint256 public constant VALIDATION_GAS_LIMIT = 500_000;
    uint256 public constant SOLVER_GAS_BUFFER = 5; // out of 100
    uint256 public constant FASTLANE_GAS_BUFFER = 125_000; // integer amount

    uint256 internal constant _EXECUTION_REFUND = (
        1 << uint256(SolverOutcome.CallReverted) | 1 << uint256(SolverOutcome.BidNotPaid)
            | 1 << uint256(SolverOutcome.CallValueTooHigh) | 1 << uint256(SolverOutcome.UnknownError)
            | 1 << uint256(SolverOutcome.CallbackFailed) | 1 << uint256(SolverOutcome.IntentUnfulfilled)
            | 1 << uint256(SolverOutcome.EVMError) | 1 << uint256(SolverOutcome.PreSolverFailed)
            | 1 << uint256(SolverOutcome.Success)
    );

    uint256 internal constant _NO_NONCE_UPDATE = (
        1 << uint256(SolverOutcome.InvalidSignature) | 1 << uint256(SolverOutcome.AlreadyExecuted)
            | 1 << uint256(SolverOutcome.InvalidNonceUnder)
    );

    uint256 internal constant _EXECUTED_WITH_ERROR = (
        1 << uint256(SolverOutcome.CallReverted) | 1 << uint256(SolverOutcome.BidNotPaid)
            | 1 << uint256(SolverOutcome.CallValueTooHigh) | 1 << uint256(SolverOutcome.UnknownError)
            | 1 << uint256(SolverOutcome.CallbackFailed) | 1 << uint256(SolverOutcome.IntentUnfulfilled)
            | 1 << uint256(SolverOutcome.PreSolverFailed) | 1 << uint256(SolverOutcome.EVMError)
    );

    uint256 internal constant _EXECUTED_SUCCESSFULLY = (1 << uint256(SolverOutcome.Success));

    uint256 internal constant _NO_USER_REFUND = (
        1 << uint256(SolverOutcome.InvalidTo) | 1 << uint256(SolverOutcome.InvalidSignature)
            | 1 << uint256(SolverOutcome.InvalidUserHash) | 1 << uint256(SolverOutcome.InvalidBidsHash)
            | 1 << uint256(SolverOutcome.GasPriceOverCap) | 1 << uint256(SolverOutcome.InvalidSequencing)
            | 1 << uint256(SolverOutcome.InvalidControlHash)
    );

    uint256 internal constant _CALLDATA_REFUND = (
        1 << uint256(SolverOutcome.InsufficientEscrow) | 1 << uint256(SolverOutcome.InvalidNonceOver)
            | 1 << uint256(SolverOutcome.UserOutOfGas) | 1 << uint256(SolverOutcome.CallValueTooHigh)
    );

    uint256 internal constant _FULL_REFUND = (
        _EXECUTION_REFUND | 1 << uint256(SolverOutcome.AlreadyExecuted) | 1 << uint256(SolverOutcome.InvalidNonceUnder)
            | 1 << uint256(SolverOutcome.PerBlockLimit) | 1 << uint256(SolverOutcome.InvalidFormat)
    );

    function canExecute(uint256 result) internal pure returns (bool) {
        return ((result >> 1) == 0);
    }

    function executionSuccessful(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_SUCCESSFULLY) != 0;
    }

    function executedWithError(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_WITH_ERROR) != 0;
    }

    function updateEscrow(uint256 result) internal pure returns (bool) {
        return !((result & _NO_NONCE_UPDATE != 0) || (result & _NO_USER_REFUND != 0));
    }
}
