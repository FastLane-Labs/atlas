//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISearcherContract } from "../interfaces/ISearcherContract.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { FastLaneErrorsEvents } from "./Emissions.sol";

import {
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    StagingCall,
    BidData,
    PayeeData,
    PaymentData
} from "../libraries/DataTypes.sol";

contract SearcherExecution is FastLaneErrorsEvents {

    // TODO: this would be the FastLane address - fill in. 
    address constant public FEE_RECIPIENT = address(0); 

    function _searcherCallExecutor(
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) internal returns (SearcherOutcome) {
        
        try this.searcherMetaWrapper(gasLimit, searcherCall) {
            return SearcherOutcome.Success;
        
        } catch Error(string memory err)  {
            if (keccak256(abi.encodePacked(err)) == _SEARCHER_BID_UNPAID) {
                // TODO: implement cheaper way to do this
                return SearcherOutcome.BidNotPaid;
            } else {
                return SearcherOutcome.CallReverted;
            }
        
        } catch {
            return SearcherOutcome.CallReverted;
        }
    }

    function searcherMetaWrapper(
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external {
        // this is external but will be called from address(this)
        
        require(msg.sender == address(this), "ERR-04 Self-Call-Only");

        // TODO: need to handle native eth
        uint256[] memory tokenBalances = new uint[](searcherCall.bids.length);
        uint256 i;

        for (; i < searcherCall.bids.length;) {
            tokenBalances[i] = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
            unchecked {++i;}
        }

        (bool success,) = ISearcherContract(searcherCall.metaTx.to).metaFlashCall{
            gas: gasLimit, 
            value: searcherCall.metaTx.value
        }(
            searcherCall.metaTx.from,
            searcherCall.metaTx.data,
            searcherCall.bids
        );

        require(success, "ERR-MW01 SearcherCallReverted");

        i = 0;
        for (; i < searcherCall.bids.length;) {
            
            require(
                ERC20(searcherCall.bids[i].token).balanceOf(address(this)) >= tokenBalances[i] + searcherCall.bids[i].bidAmount,
                "ERR-MW02 SearcherBidUnpaid"
            );
            
            unchecked {++i;}
        }
    }

    function _disbursePayments(
        uint256 protocolShare,
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) internal {
        // NOTE: the relay/frontend will verify that the bid 
        // and payments arrays are aligned
        // NOTE: pour one out for the eth mainnet homies
        // that'll need to keep their payee array short :(
        
        // declare some vars to make this trainwreck less unreadable
        PaymentData memory pmtData;
        ERC20 token;
        uint256 payment;
        uint256 bidAmount;
        uint256 remainder;
        bool callSuccess;

        uint256 i;
        uint256 k;        

        for (; i < bids.length;) {
            token = ERC20(bids[i].token);
            bidAmount = bids[i].bidAmount;
            remainder = bidAmount;

            for (; k < payeeData[i].payments.length;) {

                pmtData = payeeData[i].payments[k];
                
                payment = bidAmount * pmtData.payeePercent / (100 + protocolShare);
                remainder -= payment;

                if (pmtData.pmtSelector != bytes4(0)) {
                    // TODO: handle native token / ETH
                    SafeTransferLib.safeTransfer(token, pmtData.payee, payment);
                
                } else {
                    // TODO: formalize the args for this (or use bytes set by frontend?)
                    // (it's (address, uint256) atm)
                    // TODO: even tho we control the frontend which populates the payee
                    // info, this is dangerous af and prob shouldn't be done this way
                    // TODO: update lock for this
                    (callSuccess,) = pmtData.payee.call(
                        abi.encodeWithSelector(
                            pmtData.pmtSelector, 
                            bids[i].token,
                            payment    
                        )
                    );
                    require(callSuccess, "ERR-05 ProtoPmt");
                }
                
                // Protocol Fee is remainder
                // NOTE: this assumption does not work for native token / ETH
                SafeTransferLib.safeTransfer(token, FEE_RECIPIENT, remainder);

                unchecked{ ++k;}
            }

            unchecked{ ++i;}
        }
    }
}