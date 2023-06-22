//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct SearcherEscrow {
    uint128 total;
    uint128 escrowed;
    uint64 availableOn; // block.number when funds are available.  
    uint64 lastAccessed;
    uint32 nonce; // EOA nonce.
}

struct ProtocolProof {
    address from;
    address to;
    uint256 nonce;
    uint256 deadline;
    bytes32 userCallHash; // keccak256 of userCall.to, userCall.data
    bytes32 protocolDataHash; // keccak256 of ProtocolData struct
    bytes32 searcherChainHash; // keccak256 of the searchers' txs
}

struct Verification {
    ProtocolProof proof;
    bytes signature;
}

struct ProtocolData {
    address owner; // the protocol, not fastlane
    uint32 nonce; 
    uint16 callConfig; // bitwise
    uint16 split; // FL revenue share
}

enum CallConfig { // for readability, will get broken down into pure funcs later
    CallStaging,
    DelegateStaging,
    FwdValueStaging,
    DelegateUser,
    FwdValueUser,
    CallVerification,
    DelegateVerification,
    FwdValueVerification
}

enum SearcherSafety {
    Unset,
    Requested,
    Verified
}

struct SearcherProof {
    bytes32 previousHash;
    bytes32 targetHash;
    bytes32 userCallHash;
    uint256 index;
}

struct SearcherMetaTx {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
    uint256 maxFeePerGas; // maxFeePerGas searcher is willing to pay.  This goes to validator, not protocol or user
    bytes32 bidsHash; // searcher's backend must keccak256() their BidData array and include that in the signed meta tx, which we then verify on chain. 
    bytes data;
}

struct BidData {
    address token;
    uint256 bidAmount;
}

struct SearcherCall {
    SearcherMetaTx metaTx;
    bytes signature;
    BidData[] bids;
}

struct EscrowKey {
    address approvedCaller;
    bool makingPayments;
    bool paymentsComplete;
    uint8 callIndex;
    uint8 callMax;
    uint64 lockState; // bitwise
}

enum BaseLock {
    Unlocked,
    Pending,
    Active,
    Untrusted,
    DelegatingCall
}

enum ExecutionPhase {
    Uninitialized,
    Staging,
    UserCall,
    SearcherCalls,
    HandlingPayments,
    UserRefund,
    Verification,
    Releasing
}


/// @notice contract call set by front end to prepare state for user's call (IE token transfers to address(this))
/// @param to address to call
/// @param stagingSelector func selector to call
/// @dev This is set by the front end!
/// @dev The stagingSelector's argument types must match the user's call's argument types to properly stage the meta tx.
struct StagingCall { 
    address stagingTo;
    address verificationTo;
    uint16 callConfig;
    bytes4 stagingSelector;
    bytes4 verificationSelector;
    bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
    
    // TODO: allow option for protocol frontends (via relay) to sign this data to prevent hostile users 
    // from tampering w/ it
    // NOTE: protocols opting to sign the staging call should be strongly discouraged from doing so as 
    // the necessity for staging data to be trustless would also imply the existence of attack vectors
    // that could potentially be accessed by other means. (might be useful for CLOBs tho)
}

struct UserCall {
    address to;
    address from;
    uint256 deadline;
    uint256 gas;
    uint256 value;
    bytes data;
}

/// @notice protocol payee Data Struct
/// @param token token address (ERC20) being paid
struct PayeeData {
    address token;
    PaymentData[] payments;
}

/// @param payee address to pay
/// @param payeePercent percentage of bid to pay to payee (base 100)
/// @dev must sum to 100
struct PaymentData {
    address payee;
    uint256 payeePercent;
    bytes4 pmtSelector; // func selector (on payee contract) to call for custom pmt function. leave blank if payee receives funds via ERC20 transfer
    // TODO: formalize / customize args for pmtSelector?
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
    CallReverted,
    BidNotPaid,
    CallValueTooHigh,
    Success
}

bytes32 constant SEARCHER_TYPE_HASH =
        keccak256(
            "SearcherMetaTx(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes32 userCallHash,uint256 maxFeePerGas,bytes32 bidsHash,bytes data)"
        );

bytes32 constant PROTOCOL_TYPE_HASH =
    keccak256(
        "ProtocolProof(address from,address to,uint256 nonce,uint256 deadline,bytes32 userCallHash,bytes32 protocolDataHash,bytes32 searcherChainHash)"
    );

contract FastLaneDataTypes {

    uint256 constant public SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 constant public VALIDATION_GAS_LIMIT = 500_000;
    uint256 constant public GWEI = 1_000_000_000;
    uint256 constant public SEARCHER_GAS_BUFFER = 5; // out of 100
    uint256 constant public FASTLANE_GAS_BUFFER = 125_000; // integer amount

    
    uint256 constant internal _NO_USER_REFUND = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) |
        1 << uint256(SearcherOutcome.InvalidSequencing)
    );

    uint256 constant internal _CALLDATA_REFUND = (
        1 << uint256(SearcherOutcome.InsufficientEscrow) |
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.UserOutOfGas) |
        1 << uint256(SearcherOutcome.CallValueTooHigh) 
    );

    uint256 constant internal _FULL_REFUND = (
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat)
    );

    uint256 constant internal _EXTERNAL_REFUND = (
        1 << uint256(SearcherOutcome.LostAuction)
    );

    uint256 constant internal _EXECUTION_REFUND = (
        1 << uint256(SearcherOutcome.CallReverted) |
        1 << uint256(SearcherOutcome.BidNotPaid) |
        1 << uint256(SearcherOutcome.CallValueTooHigh) |
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
        1 << uint256(SearcherOutcome.LostAuction)
    );

    uint256 constant internal _EXECUTED_WITH_ERROR = (
        1 << uint256(SearcherOutcome.BidNotPaid) |
        1 << uint256(SearcherOutcome.CallReverted) 
    );


}
