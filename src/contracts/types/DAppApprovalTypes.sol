//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct DAppOperation {
    address to; // Atlas
    DAppApproval approval;
    bytes signature;
}

bytes32 constant DAPP_TYPE_HASH = keccak256(
    "DAppApproval(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,bytes32 controlCodeHash,bytes32 userOpHash,bytes32 callChainHash)"
);

struct DAppApproval {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 maxFeePerGas;
    uint256 nonce;
    uint256 deadline;
    bytes32 controlCodeHash; // DAppControl.codehash
    bytes32 userOpHash; // keccak256 of userOp.to, userOp.data
    bytes32 callChainHash; // keccak256 of the solvers' txs
}

struct DAppConfig {
    address to;
    uint32 callConfig;
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
    bool solverBundler;
    bool unknownBundler;
    bool forwardReturnData;
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
    SolverBundler,
    UnknownBundler,
    ForwardReturnData
}