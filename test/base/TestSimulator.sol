//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Simulator } from "../../src/contracts/helpers/Simulator.sol";
import { UserOperation } from "../../src/contracts/types/UserOperation.sol";
import { SolverOperation } from "../../src/contracts/types/SolverOperation.sol";

/// @title TestSimulator
/// @author FastLane Labs
/// @notice A test version of the Simulator contract that just exposes internal functions for testing purposes.
contract TestSimulator is Simulator {
    function estimateMetacallGasLimitComponents(
        UserOperation calldata userOp,
        SolverOperation[] memory solverOps
    )
        public
        view
        returns (uint256 metacallCalldataGas, uint256 metacallExecutionGas)
    {
        (metacallCalldataGas, metacallExecutionGas) = _estimateMetacallGasLimit(userOp, solverOps);
    }
}
