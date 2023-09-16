//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {FastLaneErrorsEvents} from "../types/Emissions.sol";

import "../types/CallTypes.sol";

import {SolverOutcome} from "../types/EscrowTypes.sol";
 
contract SolverWrapper is FastLaneErrorsEvents {
    function _solverOpWrapper(
        uint256 gasLimit,
        address environment,
        SolverOperation calldata solverOp,
        bytes memory returnData,
        bytes32 lockBytes
    ) internal returns (SolverOutcome, uint256) {
        // address(this) = Atlas/Escrow
        // msg.sender = tx.origin

        // Get current Ether balance
        uint256 currentBalance = address(this).balance;
        bool success;

        bytes memory data = abi.encodeWithSelector(
            IExecutionEnvironment(environment).solverMetaTryCatch.selector, gasLimit, currentBalance, solverOp, returnData);
        
        data = abi.encodePacked(data, lockBytes);

        (success, data) = environment.call{value: solverOp.call.value}(data);
        if (success) {
            return (SolverOutcome.Success, address(this).balance - currentBalance);
        }
        bytes4 errorSwitch = bytes4(data);

        if (errorSwitch == SolverBidUnpaid.selector) {
            return (SolverOutcome.BidNotPaid, 0);
        } else if (errorSwitch == SolverMsgValueUnpaid.selector) {
            return (SolverOutcome.CallValueTooHigh, 0);
        } else if (errorSwitch == IntentUnfulfilled.selector) {
            return (SolverOutcome.IntentUnfulfilled, 0);
        } else if (errorSwitch == SolverOperationReverted.selector) {
            return (SolverOutcome.CallReverted, 0);
        } else if (errorSwitch == SolverFailedCallback.selector) {
            return (SolverOutcome.CallbackFailed, 0);
        } else if (errorSwitch == AlteredControlHash.selector) {
            return (SolverOutcome.InvalidControlHash, 0);
        } else if (errorSwitch == PreSolverFailed.selector) {
            return (SolverOutcome.PreSolverFailed, 0);
        } else if (errorSwitch == PostSolverFailed.selector) {
            return (SolverOutcome.IntentUnfulfilled, 0);
        } else {
            return (SolverOutcome.CallReverted, 0);
        }
    }
}
