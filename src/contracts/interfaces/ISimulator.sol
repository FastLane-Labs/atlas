//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface ISimulator {
    function simUserOperation(UserOperation calldata userOp) external returns (bool);
    
    function simSolverCall(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        DAppOperation calldata verification
    ) external returns (bool);

    function simSolverCalls(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata verification
    ) external returns (bool);
}