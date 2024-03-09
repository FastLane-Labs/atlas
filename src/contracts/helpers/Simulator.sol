//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/LockTypes.sol";
import "../types/DAppApprovalTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";
import { CallBits } from "../libraries/CallBits.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Simulator is AtlasErrors {
    using CallVerification for UserOperation;
    using CallBits for uint32;

    enum Result {
        Unknown,
        VerificationSimFail,
        PreOpsSimFail,
        UserOpSimFail,
        SolverSimFail,
        PostOpsSimFail,
        SimulationPassed
    }

    address public immutable deployer;
    address public atlas;

    constructor() {
        deployer = msg.sender;
    }

    function setAtlas(address _atlas) external {
        if (msg.sender != deployer) revert Unauthorized();
        atlas = _atlas;
    }

    function simUserOperation(UserOperation calldata userOp) external payable returns (bool success) {
        // SolverOperation memory solverOp;
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        // solverOps[0] = solverOp;
        DAppOperation memory dAppOp;
        dAppOp.control = userOp.control;

        success = uint8(_errorCatcher(userOp, solverOps, dAppOp)) > uint8(Result.UserOpSimFail);
    }

    function simSolverCall(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool success)
    {
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;

        success = _errorCatcher(userOp, solverOps, dAppOp) == Result.SimulationPassed;
    }

    function simSolverCalls(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool success)
    {
        if (solverOps.length == 0) {
            return false;
        }
        success = _errorCatcher(userOp, solverOps, dAppOp) == Result.SimulationPassed;
    }

    function _errorCatcher(
        UserOperation memory userOp,
        SolverOperation[] memory solverOps,
        DAppOperation memory dAppOp
    )
        internal
        returns (Result result)
    {
        try this.metacallSimulation{ value: msg.value }(userOp, solverOps, dAppOp) {
            revert("unreachable");
        } catch (bytes memory revertData) {
            bytes4 errorSwitch = bytes4(revertData);
            if (errorSwitch == VerificationSimFail.selector) {
                result = Result.VerificationSimFail;
                console.log("Result.VerificationSimFail");
            } else if (errorSwitch == PreOpsSimFail.selector) {
                result = Result.PreOpsSimFail;
                console.log("Result.PreOpsSimFail");
            } else if (errorSwitch == UserOpSimFail.selector) {
                result = Result.UserOpSimFail;
                console.log("Result.UserOpSimFail");
            } else if (errorSwitch == SolverSimFail.selector) {
                result = Result.SolverSimFail;
                console.log("Result.SolverSimFail");
            } else if (errorSwitch == PostOpsSimFail.selector) {
                result = Result.PostOpsSimFail;
                console.log("Result.PostOpsSimFail");
            } else if (errorSwitch == SimulationPassed.selector) {
                result = Result.SimulationPassed;
                console.log("Result.SimulationPassed");
            } else {
                result = Result.Unknown;
                console.log("Result.Unknown");
            }
        }
    }

    function metacallSimulation(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        external
        payable
    {
        if (msg.sender != address(this)) revert InvalidEntryFunction();
        if (!IAtlas(atlas).metacall(userOp, solverOps, dAppOp)) {
            revert NoAuctionWinner(); // should be unreachable
        }
        revert SimulationPassed();
    }

    receive() external payable { }
    fallback() external payable { }
}
