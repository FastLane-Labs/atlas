//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

uint256 constant CALLDATA_LENGTH_PREMIUM = 32; // 16 (default) * 2

struct EscrowAccountData {
    uint128 balance;
    uint128 holds;
}

struct EscrowNonce {
    uint64 nonce;
    uint64 lastAccessed;
    uint128 withdrawalAmount;
}

// NOTE: The order is very important here for balance reconciliation.
// We _MUST_ net the balances in order from LastLook to FirstLook
// TODO: add 'dAppSignatory' option
enum Party {
    Builder, // block.coinbase
    Bundler, // tx.origin
    Sequencer, // dApp signatory
    Solver,
    User,
    DApp
}

enum SolverOutcome
// future task tracking
{
    PendingUpdate,
    ExecutionCompleted,
    UpdateCompleted,
    BlockExecution,
    // no user refund (relay error or hostile user)
    InvalidTo,
    InvalidSignature,
    InvalidUserHash,
    InvalidControlHash,
    InvalidBidsHash,
    InvalidSequencing,
    GasPriceOverCap,
    UserOutOfGas,
    // calldata user refund from solver
    InsufficientEscrow,
    InvalidNonceOver,
    // no call, but full user refund
    AlreadyExecuted,
    InvalidNonceUnder,
    PerBlockLimit, // solvers can only send one tx per block
    // if they sent two we wouldn't be able to flag builder censorship
    InvalidFormat,
    // dApp / external user refund (TODO: keep?)
    LostAuction, // a higher bidding solver was successful
    // call, with full user refund
    UnknownError,
    CallReverted,
    BidNotPaid,
    IntentUnfulfilled,
    PreSolverFailed,
    CallValueTooHigh,
    CallbackFailed,
    EVMError,
    Success
}
