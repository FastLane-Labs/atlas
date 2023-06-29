//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct Verification {
    ProtocolProof proof;
    bytes signature;
}

struct CallChainProof {
    bytes32 previousHash;
    bytes32 targetHash;
    bytes32 userCallHash;
    uint256 index;
}

struct ProtocolProof {
    address from;
    address to;
    uint256 nonce;
    uint256 deadline;
    bytes32 userCallHash; // keccak256 of userCall.to, userCall.data
    bytes32 callChainHash; // keccak256 of the searchers' txs
}