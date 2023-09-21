//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct Verification {
    address to; // Atlas
    DAppProof proof;
    bytes signature;
}

struct DAppProof {
    address from;
    address to;
    uint256 nonce;
    uint256 deadline;
    bytes32 userOpHash; // keccak256 of userOp.to, userOp.data
    bytes32 callChainHash; // keccak256 of the solvers' txs
    bytes32 controlCodeHash; // DAppControl.codehash
}
