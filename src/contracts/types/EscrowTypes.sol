//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

uint256 constant CALLDATA_LENGTH_PREMIUM = 32; // 16 (default) * 2

// bonded = total - unbonding
struct EscrowAccountBalance {
    uint112 balance;
    uint112 unbonding;
}

struct EscrowAccountAccessData {
    uint112 bonded;
    uint32 lastAccessedBlock;
    uint24 auctionWins;
    uint24 auctionFails;
    uint64 totalGasUsed;
}

enum SolverOutcome {
    // no refund (relay error or hostile user)
    InvalidSignature,
    InvalidUserHash,
    DeadlinePassed,
    InvalidTo,
    UserOutOfGas,
    AlteredControl,
    // Partial Refund but no execution
    GasPriceOverCap,
    InvalidSolver,
    PerBlockLimit, // solvers can only send one tx per block
    // if they sent two we wouldn't be able to flag builder censorship
    InsufficientEscrow,
    CallValueTooHigh,
    // execution, with full user refund
    PreSolverFailed,
    SolverOpReverted,
    PostSolverFailed,
    IntentUnfulfilled,
    BidNotPaid,
    BalanceNotReconciled,
    EVMError
}
