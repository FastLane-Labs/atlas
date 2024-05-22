//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

bytes32 constant USER_TYPEHASH = keccak256(
    "UserOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address dapp,address control,uint32 callConfig,address sessionKey,bytes32 data)"
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
    uint32 callConfig;
    address sessionKey;
    bytes data;
    bytes signature;
}
