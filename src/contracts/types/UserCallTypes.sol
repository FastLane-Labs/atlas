//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

bytes32 constant USER_TYPE_HASH = keccak256(
    "UserOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address dapp,address control,bytes32 data)"
);

struct UserOperation {
    address from; // User EOA address
    address to; // Atlas address
    uint256 value;
    uint256 gas;
    uint256 maxFeePerGas;
    uint256 nonce;
    uint256 deadline;
    address dapp; // nested "to" for user's call
    address control; // address for preOps / validation funcs
    bytes data;
    bytes signature;
}
