//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

bytes32 constant DAPP_TYPE_HASH = keccak256(
    "DAppApproval(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address control,bytes32 userOpHash,bytes32 callChainHash)"
);

struct DAppOperation {
    address from; // signor address
    address to; // Atlas address
    uint256 value;
    uint256 gas;
    uint256 maxFeePerGas;
    uint256 nonce;
    uint256 deadline;
    address control; // control
    bytes32 userOpHash; // keccak256 of userOp.to, userOp.data
    bytes32 callChainHash; // keccak256 of the solvers' txs
    bytes signature;
}

struct DAppConfig {
    address to;
    uint32 callConfig;
    address bidToken;
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
    bool verifySolverBundlerCallChainHash;
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
    VerifySolverBundlerCallChainHash,
    UnknownBundler,
    ForwardReturnData
}
