// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { UserOperation } from "../../../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../../../src/contracts/types/SolverCallTypes.sol";

import { CallVerification } from "../../../src/contracts/libraries/CallVerification.sol";

import { IAtlasVerification } from "../../../src/contracts/interfaces/IAtlasVerification.sol";
import { IDAppControl } from "../../../src/contracts/interfaces/IDAppControl.sol";

contract SolverOperationBuilder is Test {
    using CallVerification for UserOperation;

    SolverOperation solverOperation;

    function withFrom(address from) public returns (SolverOperationBuilder) {
        solverOperation.from = from;
        return this;
    }

    function withTo(address to) public returns (SolverOperationBuilder) {
        solverOperation.to = to;
        return this;
    }

    function withValue(uint256 value) public returns (SolverOperationBuilder) {
        solverOperation.value = value;
        return this;
    }

    function withGas(uint256 gas) public returns (SolverOperationBuilder) {
        solverOperation.gas = gas;
        return this;
    }

    function withMaxFeePerGas(uint256 maxFeePerGas) public returns (SolverOperationBuilder) {
        solverOperation.maxFeePerGas = maxFeePerGas;
        return this;
    }

    function withDeadline(uint256 deadline) public returns (SolverOperationBuilder) {
        solverOperation.deadline = deadline;
        return this;
    }

    function withSolver(address solver) public returns (SolverOperationBuilder) {
        solverOperation.solver = solver;
        return this;
    }

    function withControl(address control) public returns (SolverOperationBuilder) {
        solverOperation.control = control;
        return this;
    }

    function withUserOpHash(bytes32 userOpHash) public returns (SolverOperationBuilder) {
        solverOperation.userOpHash = userOpHash;
        return this;
    }

    function withUserOpHash(UserOperation memory userOperation) public returns (SolverOperationBuilder) {
        solverOperation.userOpHash = userOperation.getUserOperationHash();
        return this;
    }

    function withBidToken(address bidToken) public returns (SolverOperationBuilder) {
        solverOperation.bidToken = bidToken;
        return this;
    }

    function withBidToken(
        address control,
        UserOperation memory userOperation
    )
        public
        returns (SolverOperationBuilder)
    {
        solverOperation.bidToken = IDAppControl(control).getBidFormat(userOperation);
        return this;
    }

    function withBidToken(UserOperation memory userOperation) public returns (SolverOperationBuilder) {
        solverOperation.bidToken = IDAppControl(solverOperation.control).getBidFormat(userOperation);
        return this;
    }

    function withBidAmount(uint256 bidAmount) public returns (SolverOperationBuilder) {
        solverOperation.bidAmount = bidAmount;
        return this;
    }

    function withData(bytes memory data) public returns (SolverOperationBuilder) {
        solverOperation.data = data;
        return this;
    }

    function withSignature(bytes memory signature) public returns (SolverOperationBuilder) {
        solverOperation.signature = signature;
        return this;
    }

    function sign(address atlasVerification, uint256 privateKey) public returns (SolverOperationBuilder) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(privateKey, IAtlasVerification(atlasVerification).getSolverPayload(solverOperation));
        solverOperation.signature = abi.encodePacked(r, s, v);
        return this;
    }

    function build() public view returns (SolverOperation memory) {
        return solverOperation;
    }
}
