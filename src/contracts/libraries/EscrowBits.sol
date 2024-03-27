//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/EscrowTypes.sol";

library EscrowBits {
    // Bundler's Fault - solver doesn't owe any gas refund. SolverOp isn't executed
    uint256 internal constant _NO_REFUND = 0x000000000000000000000000000000000000000000000000000000000000003f; // 63
    /*    
        (
            1 << uint256(SolverOutcome.InvalidSignature) // <- detected by verification
                | 1 << uint256(SolverOutcome.InvalidUserHash) // <- detected by verification
                | 1 << uint256(SolverOutcome.DeadlinePassedAlt) // <- detected by escrow
                | 1 << uint256(SolverOutcome.InvalidTo) // <- detected by verification
                | 1 << uint256(SolverOutcome.UserOutOfGas) // <- detected by escrow
                | 1 << uint256(SolverOutcome.AlteredControl)
        ); // <- detected by EE
    */

    // Solver's Fault - solver *does* owe gas refund, SolverOp isn't executed
    uint256 internal constant _PARTIAL_REFUND = 0x0000000000000000000000000000000000000000000000000000000000003fc0; // 16320
    /*
        (
            1 << uint256(SolverOutcome.DeadlinePassed) // <- detected by escrow
                | 1 << uint256(SolverOutcome.GasPriceOverCap) // <- detected by verification
                | 1 << uint256(SolverOutcome.InvalidSolver) // <- detected by verification
                | 1 << uint256(SolverOutcome.PerBlockLimit) // <- detected by escrow
                | 1 << uint256(SolverOutcome.InsufficientEscrow) // <- detected by escrow
                | 1 << uint256(SolverOutcome.GasPriceBelowUsers) // <- detected by verification
                | 1 << uint256(SolverOutcome.CallValueTooHigh) // <- detected by escrow
                | 1 << uint256(SolverOutcome.PreSolverFailed)
        ); // <- detected by EE
    */

    // Solver's Fault - solver *does* owe gas refund, SolverOp *was* executed
    uint256 internal constant _FULL_REFUND = 0x00000000000000000000000000000000000000000000000000000000000fc000; // 1032192
    /*
        (
            1 << uint256(SolverOutcome.SolverOpReverted) // <- detected by EE
                | 1 << uint256(SolverOutcome.PostSolverFailed) // <- detected by EE
                | 1 << uint256(SolverOutcome.IntentUnfulfilled) // <- detected by EE
                | 1 << uint256(SolverOutcome.BidNotPaid) // <- detected by EE
                | 1 << uint256(SolverOutcome.BalanceNotReconciled) // <- detected by EE
                | 1 << uint256(SolverOutcome.EVMError)
        ); // <- default if err by EE
    */

    function canExecute(uint256 result) internal pure returns (bool) {
        return (result == 0);
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
