//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

bytes32 constant USER_TYPE_HASH = keccak256(
    "UserCall(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address control,bytes32 data)"
);

struct UserOperation {
    address to; // Atlas
    UserCall call;
    bytes signature;
}

struct UserCall {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 maxFeePerGas;
    uint256 nonce;
    uint256 deadline;
    address control; // address for preOps / validation funcs
    bytes data;
}
