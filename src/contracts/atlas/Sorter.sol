//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";
import {IAtlas} from "../interfaces/IAtlas.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";

import {CallBits} from "../libraries/CallBits.sol";
import {CallVerification} from "../libraries/CallVerification.sol";

contract Sorter {

    address immutable public atlas;
    address immutable public escrow;

    constructor(address _atlas, address _escrow) {
        atlas = _atlas;
        escrow = _escrow;
    }

    struct SortingData {
        uint256 amount;
        bool valid;
    }

    function sortBids(
        UserCall calldata userCall, 
        SearcherCall[] calldata searcherCalls
    ) external view returns (SearcherCall[] memory) {

        ProtocolCall memory protocolCall = IProtocolControl(userCall.metaTx.control).getProtocolCall();

        uint256 count = searcherCalls.length;

        (SortingData[] memory sortingData, uint256 invalid) = _getSortingData(
            protocolCall, userCall, searcherCalls, count);

        uint256[] memory sorted = _sort(sortingData, count, invalid);

        SearcherCall[] memory searcherCallsSorted = new SearcherCall[](count - invalid);

        count -= invalid;
        uint256 i = 0;

        for (;i<count;) {
            searcherCallsSorted[i] = searcherCalls[sorted[i]];
            unchecked { ++i; }
        }

        return searcherCallsSorted;
    }

    function _verifyBidFormat(
        BidData[] memory bidFormat, 
        SearcherCall calldata searcherCall
    ) internal pure returns (bool) {
        uint256 count = bidFormat.length;
        if (searcherCall.bids.length != count) {
            return false;
        }

        uint256 i;
        for (;i<count;) {
            if (searcherCall.bids[i].token != bidFormat[i].token) {
                return false;
            }
            unchecked{ ++i; }
        }
        return true;
    }

    function _verifySearcherEligibility(
        ProtocolCall memory protocolCall,
        UserMetaTx calldata userMetaTx, 
        SearcherCall calldata searcherCall
    ) internal view returns (bool) {
        // Verify that the searcher submitted the correct callhash
        bytes32 userCallHash = CallVerification.getUserCallHash(userMetaTx);
        if (searcherCall.metaTx.userCallHash != userCallHash) {
            return false;
        }

        // Make sure the searcher has enough funds escrowed
        // TODO: subtract any pending withdrawals
        uint256 searcherBalance = IEscrow(escrow).searcherEscrowBalance(searcherCall.metaTx.from);
        if (searcherBalance < searcherCall.metaTx.maxFeePerGas * searcherCall.metaTx.gas) {
            return false;
        }

        // Searchers can only do one tx per block - this prevents double counting escrow balances.
        // TODO: Add in "targetBlockNumber" as an arg?
        uint256 searcherLastActiveBlock = IEscrow(escrow).searcherLastActiveBlock(searcherCall.metaTx.from);
        if (searcherLastActiveBlock >= block.number) {
            return false;
        }

        // Make sure the searcher nonce is accurate
        uint256 nextSearcherNonce = IEscrow(escrow).nextSearcherNonce(searcherCall.metaTx.from);
        if (nextSearcherNonce != searcherCall.metaTx.nonce) {
            return false;
        }

        // Make sure that the searcher has the correct codehash for protocol control contract
        if (protocolCall.to.codehash != searcherCall.metaTx.controlCodeHash) {
            return false;
        }

        // Make sure that the searcher's maxFeePerGas matches or exceeds the user's
        if (searcherCall.metaTx.maxFeePerGas < userMetaTx.maxFeePerGas) {
            return false;
        }

        return true;
    }

    function _getSortingData(
        ProtocolCall memory protocolCall, 
        UserCall calldata userCall, 
        SearcherCall[] calldata searcherCalls,
        uint256 count
    ) internal view returns (SortingData[] memory, uint256){

        BidData[] memory bidFormat = IProtocolControl(protocolCall.to).getBidFormat(userCall.metaTx);

        SortingData[] memory sortingData = new SortingData[](count);

        uint256 i;
        uint256 invalid;
        for (;i<count;) {
            if (
                _verifyBidFormat(bidFormat, searcherCalls[i]) && 
                _verifySearcherEligibility(protocolCall, userCall.metaTx, searcherCalls[i])
            ) {
                sortingData[i] = SortingData({
                    amount: IProtocolControl(protocolCall.to).getBidValue(searcherCalls[i]),
                    valid: true
                });
                

            } else {
                sortingData[i] = SortingData({
                    amount: 0,
                    valid: false
                });
                unchecked{ ++invalid; }
            }
            unchecked{ ++i; }            
        }

        return (sortingData, invalid);
    }

    function _sort(
        SortingData[] memory sortingData,
        uint256 count,
        uint256 invalid
    ) internal pure returns (uint256[] memory) {

        uint256[] memory sorted = new uint256[](count - invalid);

        uint256 n; // outer loop counter
        uint256 i; // inner loop counter

        uint256 topBid;
        uint256 bottomBid;

        for (;invalid<count;) {

            // Reset the ceiling / floor
            topBid = 0;
            bottomBid = type(uint256).max;

            // Loop through and find the highest and lowest remaining valid bids
            for(;i<sortingData.length;) {
                if (sortingData[i].valid) {
                    if (sortingData[i].amount > topBid) {
                        sorted[n] = i;
                    }
                    if (sortingData[i].amount < bottomBid) {
                        sorted[count-1-n] = i;
                    }
                }
                unchecked {++i;}
            }

            // Mark the lowest & highest bids invalid (Used)
            sortingData[sorted[n]].valid = false;
            sortingData[sorted[count-1-n]].valid = false;

            unchecked { invalid +=2; }
            unchecked { ++n; }
        }

        return sorted;
    }
}