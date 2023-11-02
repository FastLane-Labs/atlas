//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../types/SolverCallTypes.sol";

interface IAtlasVerification {
    function getSolverPayload(SolverOperation calldata solverOp) external view returns (bytes32 payload);
    function verifySignature(SolverOperation calldata solverOp) external view returns (bool);
}