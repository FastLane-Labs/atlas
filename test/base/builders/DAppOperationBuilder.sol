// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { UserOperation } from "../../../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../../../src/contracts/types/SolverCallTypes.sol";
import { DAppOperation } from "../../../src/contracts/types/DAppApprovalTypes.sol";

import { CallVerification } from "../../../src/contracts/libraries/CallVerification.sol";

import { IDAppControl } from "../../../src/contracts/interfaces/IDAppControl.sol";
import { IAtlasVerification } from "../../../src/contracts/interfaces/IAtlasVerification.sol";

import "../../../src/contracts/types/DAppApprovalTypes.sol";

abstract contract DAppOperationBuilder is Test {
    using CallVerification for UserOperation;

    DAppOperation dappOperation;

    function withFrom(address from) public returns (DAppOperationBuilder) {
        dappOperation.from = from;
        return this;
    }

    function withTo(address to) public returns (DAppOperationBuilder) {
        dappOperation.to = to;
        return this;
    }

    function withValue(uint256 value) public returns (DAppOperationBuilder) {
        dappOperation.value = value;
        return this;
    }

    function withGas(uint256 gas) public returns (DAppOperationBuilder) {
        dappOperation.gas = gas;
        return this;
    }

    function withMaxFeePerGas(uint256 maxFeePerGas) public returns (DAppOperationBuilder) {
        dappOperation.maxFeePerGas = maxFeePerGas;
        return this;
    }

    function withNonce(uint256 nonce) public returns (DAppOperationBuilder) {
        dappOperation.nonce = nonce;
        return this;
    }

    function withNonce(address atlasVerification, address account) public returns (DAppOperationBuilder) {
        dappOperation.nonce = IAtlasVerification(atlasVerification).getNextNonce(account);
        return this;
    }

    function withDeadline(uint256 deadline) public returns (DAppOperationBuilder) {
        dappOperation.deadline = deadline;
        return this;
    }

    function withControl(address control) public returns (DAppOperationBuilder) {
        dappOperation.control = control;
        return this;
    }

    function withBundler(address bundler) public returns (DAppOperationBuilder) {
        dappOperation.bundler = bundler;
        return this;
    }

    function withUserOpHash(bytes32 userOpHash) public returns (DAppOperationBuilder) {
        dappOperation.userOpHash = userOpHash;
        return this;
    }

    function withUserOpHash(UserOperation memory userOperation) public returns (DAppOperationBuilder) {
        dappOperation.userOpHash = userOperation.getUserOperationHash();
        return this;
    }

    function withCallChainHash(bytes32 callChainHash) public returns (DAppOperationBuilder) {
        dappOperation.callChainHash = callChainHash;
        return this;
    }

    function withCallChainHash(
        UserOperation memory useroperation,
        SolverOperation[] memory solverOperations
    )
        public
        returns (DAppOperationBuilder)
    {
        DAppConfig memory dConfig = IDAppControl(useroperation.control).getDAppConfig(useroperation);
        dappOperation.callChainHash = CallVerification.getCallChainHash(dConfig, useroperation, solverOperations);
        return this;
    }

    function withSignature(bytes memory signature) public returns (DAppOperationBuilder) {
        dappOperation.signature = signature;
        return this;
    }

    function sign(address atlasVerification, uint256 privateKey) public returns (DAppOperationBuilder) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(privateKey, IAtlasVerification(atlasVerification).getDAppOperationPayload(dappOperation));
        dappOperation.signature = abi.encodePacked(r, s, v);
        return this;
    }

    function build() public view returns (DAppOperation memory) {
        return dappOperation;
    }
}
