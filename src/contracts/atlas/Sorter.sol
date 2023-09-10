//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

contract Sorter {
    using CallBits for uint16;

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

    function _sortBids(
        UserCall calldata userCall, 
        SearcherCall[] memory searcherCalls
    ) internal view returns (SearcherCall[] memory) {

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
        BidData[] memory bids
    ) internal pure returns (bool) {
        uint256 count = bidFormat.length;
        if (bids.length != count) {
            return false;
        }

        uint256 i;
        for (;i<count;) {
            if (bids[i].token != bidFormat[i].token) {
                return false;
            }
            unchecked{ ++i; }
        }
        return true;
    }

    function _verifySearcherEligibility(
        ProtocolCall memory protocolCall,
        UserMetaTx calldata userMetaTx, 
        SearcherMetaTx memory searcherMetaTx
    ) internal view returns (bool) {
        // Verify that the searcher submitted the correct callhash
        bytes32 userCallHash = CallVerification.getUserCallHash(userMetaTx);
        if (searcherMetaTx.userCallHash != userCallHash) {
            return false;
        }

        // Make sure the searcher has enough funds escrowed
        // TODO: subtract any pending withdrawals
        if (!protocolCall.callConfig.needsOnChainBids()) {
            uint256 searcherBalance = IEscrow(escrow).searcherEscrowBalance(searcherMetaTx.from);
            if (searcherBalance < searcherMetaTx.maxFeePerGas * searcherMetaTx.gas) {
                return false;
            }

            // Searchers can only do one tx per block - this prevents double counting escrow balances.
            // TODO: Add in "targetBlockNumber" as an arg?
            uint256 searcherLastActiveBlock = IEscrow(escrow).searcherLastActiveBlock(searcherMetaTx.from);
            if (searcherLastActiveBlock >= block.number) {
                return false;
            }

            // Make sure the searcher nonce is accurate
            uint256 nextSearcherNonce = IEscrow(escrow).nextSearcherNonce(searcherMetaTx.from);
            if (nextSearcherNonce != searcherMetaTx.nonce) {
                return false;
            }
        }

        // Make sure that the searcher has the correct codehash for protocol control contract
        if (protocolCall.to.codehash != searcherMetaTx.controlCodeHash) {
            return false;
        }

        // Make sure that the searcher's maxFeePerGas matches or exceeds the user's
        if (searcherMetaTx.maxFeePerGas < userMetaTx.maxFeePerGas) {
            return false;
        }

        return true;
    }

    function _getSortingData(
        ProtocolCall memory protocolCall, 
        UserCall calldata userCall, 
        SearcherCall[] memory searcherCalls,
        uint256 count
    ) internal view returns (SortingData[] memory, uint256){

        BidData[] memory bidFormat = IProtocolControl(protocolCall.to).getBidFormat(userCall.metaTx);

        SortingData[] memory sortingData = new SortingData[](count);

        uint256 i;
        uint256 invalid;
        for (;i<count;) {
            if (
                _verifyBidFormat(bidFormat, searcherCalls[i].bids) && 
                _verifySearcherEligibility(protocolCall, userCall.metaTx, searcherCalls[i].metaTx)
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