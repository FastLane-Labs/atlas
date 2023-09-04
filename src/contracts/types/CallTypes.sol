//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct UserCall {
    address to; // Atlas
    UserMetaTx metaTx;
    bytes signature;
}

struct UserMetaTx {
    address from;
    address to;
    uint256 deadline;
    uint256 gas;
    uint256 nonce;
    uint256 maxFeePerGas;
    uint256 value;
    address control; // address for staging / validation funcs
    bytes data;
}

struct SearcherCall {
    address to; // Atlas
    SearcherMetaTx metaTx;
    bytes signature;
    BidData[] bids;
}

struct SearcherMetaTx {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    uint256 maxFeePerGas; // maxFeePerGas searcher is willing to pay.  This goes to validator, not protocol or user
    bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
    bytes32 controlCodeHash; // ProtocolControl.codehash
    bytes32 bidsHash; // searcher's backend must keccak256() their BidData array and include that in the signed meta tx, which we then verify on chain.
    bytes data;
}

struct BidData {
    address token;
    uint256 bidAmount;
}

struct PayeeData {
    address token;
    PaymentData[] payments;
    bytes data;
}

struct PaymentData {
    address payee;
    uint256 payeePercent;
}

struct ProtocolCall {
    address to;
    uint16 callConfig;
}

enum CallConfig {
    Sequenced,
    CallStaging,
    TrackStagingReturnData,
    TrackUserReturnData,
    DelegateUser,
    LocalUser,
    SearcherStaging,
    SearcherFulfillment,
    CallVerification,
    ZeroSearchers,
    ReuseUserOp,
    UserBundler,
    ProtocolBundler,
    UnknownBundler
}
