//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface ISimulator {
    function simUserOperation(UserCall calldata uCall) external returns (bool);
    function simUserOperation(UserOperation calldata userOp) external returns (bool);
    
    function simSolverCall(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        DAppOperation calldata verification
    ) external returns (bool);

    function simSolverCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata verification
    ) external returns (bool);
}