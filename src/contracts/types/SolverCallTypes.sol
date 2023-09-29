//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;


bytes32 constant SOLVER_TYPE_HASH = keccak256(
    "SolverCall(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,bytes32 controlCodeHash,bytes32 userOpHash,bytes32 bidsHash,bytes data)"
);

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
    uint256 maxFeePerGas; // maxFeePerGas solver is willing to pay.  This goes to validator, not dApp or user
    uint256 nonce;
    uint256 deadline;
    bytes32 controlCodeHash; // DAppControl.codehash
    bytes32 userOpHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, solver wont be charged for gas)
    bytes32 bidsHash; // solver's backend must keccak256() their BidData array and include that in the signed meta tx, which we then verify on chain.
    bytes data;
}

struct BidData {
    address token;
    uint256 bidAmount;
}
