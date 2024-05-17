//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/LockTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/ValidCallsTypes.sol";
import "../types/EscrowTypes.sol";

import "forge-std/Test.sol"; // TODO remove

enum Result {
    Unknown,
    VerificationSimFail,
    PreOpsSimFail,
    UserOpSimFail,
    SolverSimFail,
    PostOpsSimFail,
    SimulationPassed
}

contract Simulator is AtlasErrors {
    address public immutable deployer;
    address public atlas;

    constructor() {
        deployer = msg.sender;
    }

    function setAtlas(address _atlas) external {
        if (msg.sender != deployer) revert Unauthorized();
        atlas = _atlas;
    }

    function simUserOperation(UserOperation calldata userOp)
        external
        payable
        returns (bool success, Result simResult, uint256)
    {
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dAppOp;
        dAppOp.control = userOp.control;

        (Result result, uint256 validCallsResult) = _errorCatcher(userOp, solverOps, dAppOp);
        success = uint8(result) > uint8(Result.UserOpSimFail);
        if (success) validCallsResult = uint256(ValidCallsResult.Valid);
        return (success, result, validCallsResult);
    }

    function simSolverCall(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool success, Result simResult, uint256)
    {
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;

        (Result result, uint256 solverOutcomeResult) = _errorCatcher(userOp, solverOps, dAppOp);
        success = result == Result.SimulationPassed;
        if (success) solverOutcomeResult = 0; // discard additional error uint if solver stage was successful
        return (success, result, solverOutcomeResult);
    }

    function simSolverCalls(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool success, Result simResult, uint256)
    {
        if (solverOps.length == 0) {
            // Returns number out of usual range of SolverOutcome enum to indicate no solverOps
            return (false, Result.Unknown, uint256(type(SolverOutcome).max) + 1);
        }
        (Result result, uint256 solverOutcomeResult) = _errorCatcher(userOp, solverOps, dAppOp);
        success = result == Result.SimulationPassed;
        if (success) solverOutcomeResult = 0; // discard additional error uint if solver stage was successful
        return (success, result, solverOutcomeResult);
    }

    function _errorCatcher(
        UserOperation memory userOp,
        SolverOperation[] memory solverOps,
        DAppOperation memory dAppOp
    )
        internal
        returns (Result result, uint256 additionalErrorCode)
    {
        try this.metacallSimulation{ value: msg.value }(userOp, solverOps, dAppOp) {
            revert Unreachable();
        } catch (bytes memory revertData) {
            bytes4 errorSwitch = bytes4(revertData);
            if (errorSwitch == VerificationSimFail.selector) {
                // revertData in form [bytes4, uint256] but reverts on abi.decode
                // This decodes the uint256 error code portion of the revertData
                uint256 validCallsResult;
                assembly {
                    let dataLocation := add(revertData, 0x20)
                    validCallsResult := mload(add(dataLocation, sub(mload(revertData), 32)))
                }
                result = Result.VerificationSimFail;
                additionalErrorCode = validCallsResult;
                console.log("Result.VerificationSimFail");
                console.log("ValidCallsResult:", validCallsResult);
            } else if (errorSwitch == PreOpsSimFail.selector) {
                result = Result.PreOpsSimFail;
                console.log("Result.PreOpsSimFail");
            } else if (errorSwitch == UserOpSimFail.selector) {
                result = Result.UserOpSimFail;
                console.log("Result.UserOpSimFail");
            } else if (errorSwitch == SolverSimFail.selector) {
                // Expects revertData in form [bytes4, uint256]
                uint256 solverOutcomeResult;
                assembly {
                    let dataLocation := add(revertData, 0x20)
                    solverOutcomeResult := mload(add(dataLocation, sub(mload(revertData), 32)))
                }
                result = Result.SolverSimFail;
                additionalErrorCode = solverOutcomeResult;
                console.log("Result.SolverSimFail");
                console.log("solverOutcomeResult:", solverOutcomeResult);
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

            return (result, additionalErrorCode);
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
        if (!IAtlas(atlas).metacall{ value: msg.value }(userOp, solverOps, dAppOp)) {
            revert NoAuctionWinner(); // should be unreachable
        }
        revert SimulationPassed();
    }

    receive() external payable { }
    fallback() external payable { }
}
