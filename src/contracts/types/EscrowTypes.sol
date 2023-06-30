//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct SearcherEscrow {
    uint128 total;
    uint128 escrowed;
    uint64 availableOn; // block.number when funds are available.  
    uint64 lastAccessed;
    uint32 nonce; // EOA nonce.
}

struct ValueTracker {
    uint128 starting;
    uint128 transferredIn;
    uint128 transferredOut;
    uint128 gasRebate;
}

enum SearcherOutcome {
    // future task tracking
    PendingUpdate,
    ExecutionCompleted,
    UpdateCompleted,
    BlockExecution,

    // no user refund (relay error or hostile user)
    InvalidSignature,
    InvalidUserHash,
    InvalidBidsHash,
    InvalidSequencing,
    GasPriceOverCap,
    UserOutOfGas,

    // calldata user refund from searcher
    InsufficientEscrow,
    InvalidNonceOver,

    // no call, but full user refund
    AlreadyExecuted,
    InvalidNonceUnder,
    PerBlockLimit, // searchers can only send one tx per block 
    // if they sent two we wouldn't be able to flag builder censorship
    InvalidFormat,

    // protocol / external user refund (TODO: keep?)
    LostAuction, // a higher bidding searcher was successful
    
    // call, with full user refund
    UnknownError,
    CallReverted,
    BidNotPaid,
    CallValueTooHigh,
    CallbackFailed,
    Success
}

bytes32 constant SEARCHER_TYPE_HASH =
        keccak256(
            "SearcherMetaTx(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes32 userCallHash,uint256 maxFeePerGas,bytes32 bidsHash,bytes data)"
        );
