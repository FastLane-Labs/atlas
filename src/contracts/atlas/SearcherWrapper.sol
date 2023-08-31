//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {FastLaneErrorsEvents} from "./Emissions.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import {SearcherOutcome} from "../types/EscrowTypes.sol";
 
contract SearcherWrapper is FastLaneErrorsEvents {
    function _searcherCallWrapper(
        uint256 gasLimit,
        address environment,
        SearcherCall calldata searcherCall,
        bytes memory data, //stagingReturnData
        bytes32 lockBytes
    ) internal returns (SearcherOutcome, uint256) {
        // address(this) = Atlas/Escrow
        // msg.sender = tx.origin

        // Get current Ether balance
        uint256 currentBalance = address(this).balance;
        bool success;

        data = abi.encodeWithSelector(
            IExecutionEnvironment(environment).searcherMetaTryCatch.selector, gasLimit, currentBalance, searcherCall, data);
        
        data = abi.encodePacked(data, lockBytes);

        (success, data) = environment.call{value: searcherCall.metaTx.value}(data);
        if (success) {
            return (SearcherOutcome.Success, address(this).balance - currentBalance);
        }
        bytes4 errorSwitch = bytes4(data);

        if (errorSwitch == SearcherBidUnpaid.selector) {
            return (SearcherOutcome.BidNotPaid, 0);
        } else if (errorSwitch == SearcherMsgValueUnpaid.selector) {
            return (SearcherOutcome.CallValueTooHigh, 0);
        } else if (errorSwitch == IntentUnfulfilled.selector) {
            return (SearcherOutcome.IntentUnfulfilled, 0);
        } else if (errorSwitch == SearcherCallReverted.selector) {
            return (SearcherOutcome.CallReverted, 0);
        } else if (errorSwitch == SearcherFailedCallback.selector) {
            return (SearcherOutcome.CallbackFailed, 0);
        } else if (errorSwitch == AlteredControlHash.selector) {
            return (SearcherOutcome.InvalidControlHash, 0);
        } else if (errorSwitch == SearcherStagingFailed.selector) {
            return (SearcherOutcome.SearcherStagingFailed, 0);
        } else if (errorSwitch == SearcherVerificationFailed.selector) {
            return (SearcherOutcome.IntentUnfulfilled, 0);
        } else {
            return (SearcherOutcome.CallReverted, 0);
        }
    }
}
