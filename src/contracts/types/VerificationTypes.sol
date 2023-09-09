//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct Verification {
    address to; // Atlas
    ProtocolProof proof;
    bytes signature;
}

struct ProtocolProof {
    address from;
    address to;
    uint256 nonce;
    uint256 deadline;
    bytes32 userCallHash; // keccak256 of userCall.to, userCall.data
    bytes32 callChainHash; // keccak256 of the searchers' txs
    bytes32 controlCodeHash; // ProtocolControl.codehash
}
