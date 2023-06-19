//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

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
    GasPriceOverCap,
    UserOutOfGas,

    // calldata user refund from searcher
    InsufficientEscrow,
    InvalidNonceOver,

    // no call, but full user refund
    AlreadyExecuted,
    InvalidNonceUnder,
    PerBlockLimit, // searchers can only send one tx per block 
    // (b/c if they sent two we wouldn't be able to flag
    // builder censorship)
    InvalidFormat,

    // protocol / external user refund (TODO: keep?)
    NotWinner, // a higher bidding searcher was successful
    
    // call, with full user refund
    CallReverted,
    BidNotPaid,
    Success
}

contract FastLaneDataTypes {

    uint256 constant public SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 constant public VALIDATION_GAS_LIMIT = 500_000;
    uint256 constant public GWEI = 1_000_000_000;
    uint256 constant public SEARCHER_GAS_BUFFER = 5; // out of 100

    bytes32 internal constant _TYPE_HASH =
        keccak256("SearcherMetaTx(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes32 userCallHash,uint256 maxFeePerGas,bytes32 bidsHash,bytes data)");

    uint256 constant internal _NO_REFUND = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) 
    );

    uint256 constant internal _CALLDATA_REFUND = (
        1 << uint256(SearcherOutcome.InsufficientEscrow) |
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.UserOutOfGas) 
    );

    uint256 constant internal _FULL_REFUND = (
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat)
    );

    uint256 constant internal _EXTERNAL_REFUND = (
        1 << uint256(SearcherOutcome.NotWinner)
    );

    uint256 constant internal _EXECUTION_REFUND = (
        1 << uint256(SearcherOutcome.CallReverted) |
        1 << uint256(SearcherOutcome.BidNotPaid) |
        1 << uint256(SearcherOutcome.Success)
    );

    uint256 constant internal _NO_NONCE_UPDATE = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder)
    );

    uint256 constant internal _BLOCK_VALID_EXECUTION = (
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) |
        1 << uint256(SearcherOutcome.UserOutOfGas) |
        1 << uint256(SearcherOutcome.NotWinner)
    );


}
