//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IAtlas} from "../interfaces/IAtlas.sol";

import {UserSimulationFailed, UserUnexpectedSuccess, UserSimulationSucceeded} from "../types/Emissions.sol";

import {FastLaneErrorsEvents} from "../types/Emissions.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/LockTypes.sol";
import "../types/DAppApprovalTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Simulator is FastLaneErrorsEvents {
    using CallVerification for UserCall;
    using CallBits for uint32;

    enum Result {
        Unknown,
        FailedToFailSimFail,
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
        require(msg.sender == deployer, "err - invalid sender");
        atlas = _atlas;
    }

    function simUserOperation(UserCall calldata uCall) external payable returns (bool success) {
        UserOperation memory userOp;
        userOp.call = uCall;
        userOp.to = atlas;
       
        DAppConfig memory dConfig = DAppConfig(uCall.control, CallBits.buildCallConfig(uCall.control));
        SolverOperation memory solverOp;
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;
        DAppOperation memory dAppOp; 
        dAppOp.approval.controlCodeHash = dConfig.to.codehash;

        (Result result,,,) = _errorCatcher(dConfig, userOp, solverOps, dAppOp);
        success = uint8(result) > uint8(Result.UserOpSimFail);
    }

    function simUserOperation(UserOperation calldata userOp) external payable returns (bool success) {
        DAppConfig memory dConfig = DAppConfig(userOp.call.control, CallBits.buildCallConfig(userOp.call.control));
        // SolverOperation memory solverOp;
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        // solverOps[0] = solverOp;
        DAppOperation memory dAppOp; 
        dAppOp.approval.controlCodeHash = dConfig.to.codehash;

        (Result result,,,) = _errorCatcher(dConfig, userOp, solverOps, dAppOp);
        success = uint8(result) > uint8(Result.UserOpSimFail);
    }

    function simSolverCall(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        DAppOperation calldata dAppOp 
    ) external payable returns (bool success,  uint256 gasUsed, uint256 gasRebated, uint256 solverIndex) {
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;
        
        Result result;
        (result, gasUsed, gasRebated, solverIndex) = _errorCatcher(dConfig, userOp, solverOps, dAppOp);
        success = result == Result.SimulationPassed;
        console.log("gasUsed    - ",gasUsed);
        console.log("gasRebated - ",gasRebated);
    }

    function simSolverCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp 
    ) external payable returns (bool success, uint256 gasUsed, uint256 gasRebated, uint256 solverIndex) {
        if (solverOps.length == 0) {
            return (false, 0, 0, 0);
        }
        Result result;
        (result, gasUsed, gasRebated, solverIndex) = _errorCatcher(dConfig, userOp, solverOps, dAppOp);
        success = result == Result.SimulationPassed;
        console.log("gasUsed    - ",gasUsed);
        console.log("gasRebated - ",gasRebated);
    }

    function _errorCatcher(
        DAppConfig memory dConfig,
        UserOperation memory userOp,
        SolverOperation[] memory solverOps,
        DAppOperation memory dAppOp 
    ) internal returns (Result result, uint256 gasUsed, uint256 gasRebated, uint256 solverIndex) {
        
        gasUsed = gasleft();

        try this.metacallSimulation{value: msg.value}(dConfig, userOp, solverOps, dAppOp) {
            revert FailedToFailSimFail();
        }
        catch (bytes memory revertData) {
            
            gasUsed -= gasleft();

            bytes4 errorSwitch = bytes4(revertData);
            if (errorSwitch == PreOpsSimFail.selector) {
                result = Result.PreOpsSimFail;
            } else if (errorSwitch == UserOpSimFail.selector) {
                result = Result.UserOpSimFail;
            } else if (errorSwitch == SolverSimFail.selector) {
                result = Result.SolverSimFail;
            } else if (errorSwitch == PostOpsSimFail.selector) {
                result = Result.PostOpsSimFail;
            } else if (errorSwitch == FailedToFailSimFail.selector) {
                result = Result.FailedToFailSimFail;
            } else if (errorSwitch == SimulationPassed.selector) {
                result = Result.SimulationPassed;
                uint256 accruedGasRebate;
                assembly {
                    accruedGasRebate := mload(add(mload(revertData), 4))
                    solverIndex := mload(add(mload(revertData), 36))
                }
                gasRebated = accruedGasRebate / tx.gasprice;
                return (Result.SimulationPassed, gasUsed, gasRebated, solverIndex);

            } else {
                revert FailedToFailSimFail();
            }
        }
    }

    function metacallSimulation(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp 
    ) external payable {
        require(msg.sender == address(this), "invalid entry func");
        IAtlas(atlas).metacall(dConfig, userOp, solverOps, dAppOp);
        revert FailedToFailSimFail();
    }

    receive() external payable {}

    fallback() external payable {}
}
