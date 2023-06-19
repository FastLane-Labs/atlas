//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IHandler } from "../interfaces/IHandler.sol";
import { ISearcherEscrow } from "../interfaces/ISearcherEscrow.sol";
import { ISearcherContract } from "../interfaces/ISearcherContract.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { FastLaneErrorsEvents } from "./Emissions.sol";

import { ThogLockLib } from "./ThogLock.sol";


contract FastLaneProtoHandler is IHandler, FastLaneErrorsEvents {

    uint256 constant public SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 constant public VALIDATION_GAS_LIMIT = 500_000;

    bytes32 constant internal _SEARCHER_BID_UNPAID = keccak256(abi.encodePacked("SearcherBidUnpaid"));
    bytes32 constant internal _SEARCHER_CALL_REVERTED = keccak256(abi.encodePacked("SearcherCallReverted"));

    address immutable internal _factory;
    address immutable internal _escrow;

    uint256 immutable internal _protocolShare;

    constructor(
        uint16 protocolShare, 
        address escrow

    ) {
        _factory = msg.sender; // TODO: hardcode the factory?
        _escrow = escrow;

        _protocolShare = uint256(protocolShare);

        // meant to be a single-shot execution environment
        //selfdestruct(payable(_factory));
    
    } 

    function protoCall( // haha get it?
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable {

        // keyCode is in memory - should be immune to tampering by malicious delegatecall
        uint256 keyCode = uint256(keccak256(abi.encodePacked(userCall.data, userCall.from)));

        // verify that the staging data provided by frontend was built around the 
        // actual user call.  
        bytes32 userCallHash = keccak256(abi.encodePacked(userCall.to, userCall.data));

        // NOTE: the stagingCall can be manipulated by an adversarial user.
        // this first check is meant as a gas-saving courtesy for frontend errors. 
        require(userCallHash == stagingCall.userCallHash, "ERR-01 UserCalldata");

        // declare some variables
        bool callSuccess; // reuse memory variable
        bytes memory stagingData; // capture any pre-execution state variables the protocol may need
        bytes memory returnData; // capture any pre-execution state variables the protocol may need

        // Stage the execution environment for the user, if necessary
        // NOTE: this is a trusted delegatecall... approve & trusted protocols only
        // NOTE: staging will almost certainly be auto-disabled for any upgradeable contracts
        if (stagingCall.stagingSelector != bytes4(0)) {
            (callSuccess, stagingData) = stagingCall.to.delegatecall(
                    bytes.concat(stagingCall.stagingSelector, userCall.data[4:])
            );
            require(callSuccess, "ERR-02 Staging");
        }

        // Do the user's call
        (callSuccess, returnData) = userCall.to.call(userCall.data);
        require(callSuccess, "ERR-03 UserCall");

        // init some vars for the searcher loop
        uint256 result;
        uint256 gasWaterMark = gasleft();
        uint256 gasLimit; 
        uint256 i; // init at 0
        callSuccess = false;

        for (; i < searcherCalls.length;) {

            (result, gasLimit) = ISearcherEscrow(_escrow).verify(
                userCallHash,
                callSuccess,
                searcherCalls[i]
            );

            if (callSuccess) {
                result |= 1 << uint256(SearcherOutcome.NotWinner);
            } 
            
            if (gasWaterMark < VALIDATION_GAS_LIMIT + SEARCHER_GAS_LIMIT) {
                // Make sure to leave enough gas for protocol validation calls
                result |= 1 << uint256(SearcherOutcome.UserOutOfGas);
            } 
            
            if (tx.gasprice > searcherCalls[i].metaTx.maxFeePerGas) {
                result |= 1 << uint256(SearcherOutcome.GasPriceOverCap);
            }

            // If there are no errors, attempt to execute
            // NOTE: the lowest bit is a tracker (PendingUpdate) and can be ignored
            if ((result >>1) == 0) {
                result |= (
                    1 << uint256(_searcherCallExecutor(gasLimit, searcherCalls[i])) |
                    1 << uint256(SearcherOutcome.ExecutionCompleted)
                );
            }

            if (result & 1 << uint256(SearcherOutcome.PendingUpdate) == 0) {
                ISearcherEscrow(_escrow).update(
                    gasWaterMark,
                    result,
                    searcherCalls[i]
                );
            }

            if (
                !(callSuccess) && 
                !(result & 1 << uint256(SearcherOutcome.ExecutionCompleted) == 0)
            ) { 
                if (result & 1 << uint256(SearcherOutcome.Success)  == 0) {
                    callSuccess = true;

                    // process protocol payments
                    _handlePayments(searcherCalls[i].bids, payeeData);
                    // TODO: who should pay gas cost of payments?
                }
            }

            keyCode = ThogLockLib.turnKeyUnsafe(keyCode, searcherCalls[i]);

            unchecked { ++i; }
            gasWaterMark = gasleft();
        }

        // Run a post-searcher verification check with the data from the staging call
        if (stagingCall.verificationSelector != bytes4(0)) {
            // Unlike the staging call, this isn't delegatecall
            (callSuccess,) = stagingCall.to.call(
                abi.encodeWithSelector(stagingCall.verificationSelector, stagingData)
            );
            require(callSuccess, "ERR-07 Verification");
        }

        // unlock the handler, escrow, and factory
        // NOTE: handler key is unreliable, and while escrow and factory
        // key can be easily discovered, the unlocking mechanism is only
        // concerned with charging the searchers responsible for their
        // rebates, hence the ECDSA check and the doublespend check at the
        // escrow level. 
        uint256 gasRebate = ThogLockLib.initThogUnlock(keyCode, _escrow);

        // handle gas rebate
        SafeTransferLib.safeTransferETH(
            userCall.from, 
            gasRebate
        );
    }

    function _handlePayments(
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) internal {
        // NOTE: the relay/frontend will verify that the bid 
        //and payments arrays are aligned
        // NOTE: pour one out for the eth mainnet homies
        // that'll need to keep their payee array short :(
        
        // declare some vars to make this trainwreck less unreadable
        PaymentData memory pmtData;
        ERC20 token;
        uint256 payment;
        uint256 bidAmount;
        bool callSuccess;

        uint256 i;
        uint256 k;        

        for (; i < bids.length;) {
            token = ERC20(bids[i].token);
            bidAmount = bids[i].bidAmount;

            for (; k < payeeData[i].payments.length;) {

                pmtData = payeeData[i].payments[k];
                
                payment = bidAmount * pmtData.payeePercent / (100 + _protocolShare);

                if (pmtData.pmtSelector != bytes4(0)) {
                    // TODO: handle native token / ETH
                    SafeTransferLib.safeTransfer(token, pmtData.payee, payment);
                
                } else {
                    // TODO: formalize the args for this (or use bytes set by frontend?)
                    // (it's (address, uint256) atm)
                    // TODO: even tho we control the frontend which populates the payee
                    // info, this is dangerous af and prob shouldn't be done this way
                    (callSuccess,) = pmtData.payee.delegatecall(
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
                SafeTransferLib.safeTransfer(token, _factory, token.balanceOf(address(this)));

                unchecked{ ++k;}
            }

            unchecked{ ++i;}
        }
    }

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
}
