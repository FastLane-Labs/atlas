//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/EscrowTypes.sol";

library EscrowBits {
    uint256 public constant SOLVER_GAS_LIMIT = 1_000_000;
    uint256 public constant VALIDATION_GAS_LIMIT = 500_000;
    uint256 public constant SOLVER_GAS_BUFFER = 5; // out of 100
    uint256 public constant FASTLANE_GAS_BUFFER = 125_000; // integer amount

    // Bundler's Fault - solver doesn't owe any gas refund. SolverOp isn't executed
    uint256 internal constant _NO_REFUND = (
        1 << uint256(SolverOutcome.InvalidSignature) // <- detected by verification
            | 1 << uint256(SolverOutcome.InvalidUserHash) // <- detected by verification
            | 1 << uint256(SolverOutcome.DeadlinePassedAlt) // <- detected by escrow
            | 1 << uint256(SolverOutcome.InvalidTo) // <- detected by verification
            | 1 << uint256(SolverOutcome.UserOutOfGas) // <- detected by escrow
            | 1 << uint256(SolverOutcome.AlteredControl) // <- detected by EE
            | 1 << uint256(SolverOutcome.GasPriceBelowUsers)
    ); // <- detected by verification

    // Solver's Fault - solver *does* owe gas refund, SolverOp isn't executed
    uint256 internal constant _PARTIAL_REFUND = (
        1 << uint256(SolverOutcome.DeadlinePassed) // <- detected by escrow
            | 1 << uint256(SolverOutcome.GasPriceOverCap) // <- detected by verification
            | 1 << uint256(SolverOutcome.InvalidSolver) // <- detected by verification
            | 1 << uint256(SolverOutcome.PerBlockLimit) // <- detected by escrow
            | 1 << uint256(SolverOutcome.InsufficientEscrow) // <- detected by escrow
            | 1 << uint256(SolverOutcome.CallValueTooHigh) // <- detected by escrow
            | 1 << uint256(SolverOutcome.PreSolverFailed)
    ); // <- detected by EE

    // Solver's Fault - solver *does* owe gas refund, SolverOp *was* executed
    uint256 internal constant _FULL_REFUND = (
        1 << uint256(SolverOutcome.SolverOpReverted) // <- detected by EE
            | 1 << uint256(SolverOutcome.PostSolverFailed) // <- detected by EE
            | 1 << uint256(SolverOutcome.IntentUnfulfilled) // <- detected by EE
            | 1 << uint256(SolverOutcome.BidNotPaid) // <- detected by EE
            | 1 << uint256(SolverOutcome.BalanceNotReconciled) // <- detected by EE
            | 1 << uint256(SolverOutcome.EVMError)
    ); // <- default if err by EE

    function canExecute(uint256 result) internal pure returns (bool) {
        return (result == 0);
    }

    function noRefund(uint256 result) internal pure returns (bool) {
        return ((result & _NO_REFUND) != 0);
    }

    // NOTE: PartialRefunds mean that the tx isn't executed but solver is still liable
    // for some gas costs.
    function partialRefund(uint256 result) internal pure returns (bool) {
        return ((result & _PARTIAL_REFUND) != 0);
    }

    function executionSuccessful(uint256 result) internal pure returns (bool) {
        return (result == 0);
    }

    function executedWithError(uint256 result) internal pure returns (bool) {
        return (result & _FULL_REFUND) != 0;
    }

    function updateEscrow(uint256 result) internal pure returns (bool) {
        // dont update solver escrow if they don't need to refund gas
        // returns true is solver doesn't get to bypass the refund.
        return (result & _NO_REFUND == 0);
    }
}
