//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ICallExecution } from "../interfaces/ICallExecution.sol";

import { FastLaneErrorsEvents } from "./Emissions.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";
import { SearcherOutcome } from "../types/EscrowTypes.sol";

contract SearcherWrapper is FastLaneErrorsEvents {

    function _searcherCallWrapper(
        CallChainProof calldata proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) internal returns (SearcherOutcome, uint256) {
        // address(this) = Escrow 
        // msg.sender = ExecutionEnvironment

        // Call the execution environment
        try ICallExecution(msg.sender).searcherMetaTryCatch(
            proof, gasLimit, searcherCall
        ) {
            return (SearcherOutcome.Success, 0);
        
        } catch Error(string memory err)  {
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