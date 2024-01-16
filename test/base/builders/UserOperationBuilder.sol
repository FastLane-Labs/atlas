// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { UserOperation } from "src/contracts/types/UserCallTypes.sol";

import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";

contract UserOperationBuilder is Test {
    UserOperation userOperation;

    function withFrom(address from) public returns (UserOperationBuilder) {
        userOperation.from = from;
        return this;
    }

    function withTo(address to) public returns (UserOperationBuilder) {
        userOperation.to = to;
        return this;
    }

    function withValue(uint256 value) public returns (UserOperationBuilder) {
        userOperation.value = value;
        return this;
    }

    function withGas(uint256 gas) public returns (UserOperationBuilder) {
        userOperation.gas = gas;
        return this;
    }

    function withMaxFeePerGas(uint256 maxFeePerGas) public returns (UserOperationBuilder) {
        userOperation.maxFeePerGas = maxFeePerGas;
        return this;
    }

    function withNonce(uint256 nonce) public returns (UserOperationBuilder) {
        userOperation.nonce = nonce;
        return this;
    }

    function withNonce(address atlasVerification) public returns (UserOperationBuilder) {
        // Assumes sequenced = false. Use withNonce(address, bool) to specify sequenced.
        userOperation.nonce = IAtlasVerification(atlasVerification).getNextNonce(userOperation.from, false);
        return this;
    }

    function withNonce(address atlasVerification, bool sequenced) public returns (UserOperationBuilder) {
        userOperation.nonce = IAtlasVerification(atlasVerification).getNextNonce(userOperation.from, sequenced);
        return this;
    }

    function withNonce(address atlasVerification, address account) public returns (UserOperationBuilder) {
        // Assumes sequenced = false. Use withNonce(address, address, bool) to specify sequenced.
        userOperation.nonce = IAtlasVerification(atlasVerification).getNextNonce(account, false);
        return this;
    }

    function withNonce(
        address atlasVerification,
        address account,
        bool sequenced
    )
        public
        returns (UserOperationBuilder)
    {
        userOperation.nonce = IAtlasVerification(atlasVerification).getNextNonce(account, sequenced);
        return this;
    }

    function withDeadline(uint256 deadline) public returns (UserOperationBuilder) {
        userOperation.deadline = deadline;
        return this;
    }

    function withDapp(address dapp) public returns (UserOperationBuilder) {
        userOperation.dapp = dapp;
        return this;
    }

    function withControl(address control) public returns (UserOperationBuilder) {
        userOperation.control = control;
        return this;
    }

    function withSessionKey(address sessionKey) public returns (UserOperationBuilder) {
        userOperation.sessionKey = sessionKey;
        return this;
    }

    function withData(bytes memory data) public returns (UserOperationBuilder) {
        userOperation.data = data;
        return this;
    }

    function withSignature(bytes memory signature) public returns (UserOperationBuilder) {
        userOperation.signature = signature;
        return this;
    }

    function sign(address atlasVerification, uint256 privateKey) public returns (UserOperationBuilder) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(privateKey, IAtlasVerification(atlasVerification).getUserOperationPayload(userOperation));
        userOperation.signature = abi.encodePacked(r, s, v);
        return this;
    }

    function build() public returns (UserOperation memory) {
        if (userOperation.nonce == 0) userOperation.nonce = 1;
        return userOperation;
    }

    function signAndBuild(address atlasVerification, uint256 privateKey) public returns (UserOperation memory) {
        if (userOperation.nonce == 0) userOperation.nonce = 1;
        sign(atlasVerification, privateKey);
        return userOperation;
    }
}
