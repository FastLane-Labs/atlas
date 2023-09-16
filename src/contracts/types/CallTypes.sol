//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct UserOperation {
    address to; // Atlas
    UserCall call;
    bytes signature;
}

struct UserCall {
    address from;
    address to;
    uint256 deadline;
    uint256 gas;
    uint256 nonce;
    uint256 maxFeePerGas;
    uint256 value;
    address control; // address for preOps / validation funcs
    bytes data;
}

struct SolverOperation {
    address to; // Atlas
    SolverCall call;
    bytes signature;
    BidData[] bids;
}

struct SolverCall {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    uint256 maxFeePerGas; // maxFeePerGas solver is willing to pay.  This goes to validator, not protocol or user
    bytes32 userOpHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, solver wont be charged for gas)
    bytes32 controlCodeHash; // DAppControl.codehash
    bytes32 bidsHash; // solver's backend must keccak256() their BidData array and include that in the signed meta tx, which we then verify on chain.
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

struct DAppConfig {
    address to;
    uint16 callConfig;
}

struct CallConfig {
    bool sequenced;
    bool requirePreOps;
    bool trackPreOpsReturnData;
    bool trackUserReturnData;
    bool delegateUser;
    bool localUser;
    bool preSolver;
    bool postSolver;
    bool requirePostOps;
    bool zeroSolvers;
    bool reuseUserOp;
    bool userBundler;
    bool dAppBundler;
    bool unknownBundler;
}

enum CallConfigIndex {
    Sequenced,
    RequirePreOps,
    TrackPreOpsReturnData,
    TrackUserReturnData,
    DelegateUser,
    LocalUser,
    PreSolver,
    PostSolver,
    RequirePostOpsCall,
    ZeroSolvers,
    ReuseUserOp,
    UserBundler,
    DAppBundler,
    UnknownBundler
}
