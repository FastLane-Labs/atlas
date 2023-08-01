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
        SearcherCall calldata searcherCall,
        uint256 gasLimit,
        address environment
    ) internal returns (SearcherOutcome, uint256) {
        // address(this) = Escrow
        // msg.sender = ExecutionEnvironment

        // Get current Ether balance
        uint256 currentBalance = address(this).balance;

        // Call the execution environment
        try IExecutionEnvironment(environment).searcherMetaTryCatch{value: searcherCall.metaTx.value}(
            gasLimit, currentBalance, searcherCall
        ) {
            return (SearcherOutcome.Success, address(this).balance - currentBalance);
        } catch Error(string memory err) {
            bytes32 errorSwitch = keccak256(abi.encodePacked(err));

            if (errorSwitch == _SEARCHER_BID_UNPAID) {
                return (SearcherOutcome.BidNotPaid, 0);
            } else if (errorSwitch == _SEARCHER_MSG_VALUE_UNPAID) {
                return (SearcherOutcome.CallValueTooHigh, 0);
            } else if (errorSwitch == _SEARCHER_CALL_REVERTED) {
                return (SearcherOutcome.CallReverted, 0);
            } else if (errorSwitch == _SEARCHER_FAILED_CALLBACK) {
                return (SearcherOutcome.CallbackFailed, 0);
            } else if (errorSwitch == _ALTERED_USER_HASH) {
                return (SearcherOutcome.InvalidUserHash, 0);
            } else if (errorSwitch == _HASH_CHAIN_BROKEN) {
                return (SearcherOutcome.InvalidSequencing, 0);
            } else {
                return (SearcherOutcome.EVMError, 0);
            }
        } catch {
            return (SearcherOutcome.CallReverted, 0);
        }
    }
}
