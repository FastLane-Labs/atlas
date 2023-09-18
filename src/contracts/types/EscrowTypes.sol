//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

uint256 constant CALLDATA_LENGTH_PREMIUM = 32; // 16 (default) * 2

struct SolverEscrow {
    uint128 total;
    uint32 nonce; // EOA nonce.
    uint64 lastAccessed; // block.number
}

struct SolverWithdrawal {
    uint128 escrowed;
    uint64 availableOn; // block.number when funds are available.
}

struct GasDonation {
    address recipient;
    uint32 net;
    uint32 cumulative;
}

enum SolverOutcome
// future task tracking
{
    PendingUpdate,
    ExecutionCompleted,
    UpdateCompleted,
    BlockExecution,
    // no user refund (relay error or hostile user)
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
    // protocol / external user refund (TODO: keep?)
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

bytes32 constant SOLVER_TYPE_HASH = keccak256(
    "SolverCall(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes32 userOpHash,bytes32 controlCodeHash,uint256 maxFeePerGas,bytes32 bidsHash,bytes data)"
);
