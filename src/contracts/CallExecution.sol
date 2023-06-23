//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISearcherContract } from "../interfaces/ISearcherContract.sol";
import { ICallExecution } from "../interfaces/ICallExecution.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { FastLaneErrorsEvents } from "./Emissions.sol";
import { BitStuff } from "./BitStuff.sol"; 

import {
    SearcherProof,
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    StagingCall,
    BidData,
    PayeeData,
    PaymentData,
    UserCall,
    CallConfig
} from "../libraries/DataTypes.sol";

string constant SEARCHER_BID_UNPAID = "SearcherBidUnpaid";
bytes32 constant _SEARCHER_BID_UNPAID = keccak256(abi.encodePacked(SEARCHER_BID_UNPAID));

string constant SEARCHER_MSG_VALUE_UNPAID = "SearcherMsgValueNotRepaid";
bytes32 constant _SEARCHER_MSG_VALUE_UNPAID = keccak256(abi.encodePacked(SEARCHER_MSG_VALUE_UNPAID));

string constant SEARCHER_CALL_REVERTED = "SearcherCallReverted";
bytes32 constant _SEARCHER_CALL_REVERTED = keccak256(abi.encodePacked(SEARCHER_CALL_REVERTED));

string constant ALTERED_USER_HASH = "AlteredUserCalldataHash";
bytes32 constant _ALTERED_USER_HASH = keccak256(abi.encodePacked(ALTERED_USER_HASH));

string constant INVALID_SEARCHER_HASH = "InvalidSearcherCalldataHash";
bytes32 constant _INVALID_SEARCHER_HASH = keccak256(abi.encodePacked(INVALID_SEARCHER_HASH));

string constant HASH_CHAIN_BROKEN = "CalldataHashChainMismatch";
bytes32 constant _HASH_CHAIN_BROKEN = keccak256(abi.encodePacked(HASH_CHAIN_BROKEN));

// string constant SEARCHER_ETHER_BID_UNPAID = "SearcherMsgValueNotRepaid";
// bytes32 constant _SEARCHER_ETHER_BID_UNPAID = keccak256(abi.encodePacked(SEARCHER_ETHER_BID_UNPAID));

library CallChain {
    function next(SearcherProof memory self, bytes32[] memory executionHashChain) internal pure returns (SearcherProof memory) {
        unchecked { ++self.index; }
        self.previousHash = self.targetHash;
        self.targetHash = executionHashChain[self.index];
        return self;
    }

    function prove(SearcherProof memory self, address from, bytes memory data, bool isDelegated) internal pure {
        require(self.targetHash == keccak256(
                abi.encodePacked(
                    self.previousHash,
                    from,
                    data,
                    isDelegated, 
                    self.index
                )
            ), HASH_CHAIN_BROKEN
        );
    }
}

contract EscrowExecution is BitStuff {

    function _searcherCallWrapper(
        SearcherProof memory proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) internal returns (SearcherOutcome, uint256) {
        // Called by the escrow contract, with msg.sender as the execution environment

        // Call the execution environment
        try ICallExecution(msg.sender).searcherMetaTryCatch(
            proof, gasLimit, searcherCall
        ) returns (uint256 searcherValueTransfer) {
            return (SearcherOutcome.Success, searcherValueTransfer);
        
        // TODO: implement cheaper way to do this
        } catch Error(string memory err)  {
            
            bytes32 errorSwitch = keccak256(abi.encodePacked(err));

            if (errorSwitch == _SEARCHER_BID_UNPAID) {
                return (SearcherOutcome.BidNotPaid, 0);

            } else if (errorSwitch == _SEARCHER_MSG_VALUE_UNPAID) {
                return (SearcherOutcome.CallValueTooHigh, 0);
            
            } else if (errorSwitch == _SEARCHER_CALL_REVERTED) {
                return (SearcherOutcome.CallReverted, 0);

            } else if (errorSwitch == _ALTERED_USER_HASH) {
                return (SearcherOutcome.InvalidUserHash, 0);
            
            } else if (errorSwitch == _HASH_CHAIN_BROKEN) {
                return (SearcherOutcome.InvalidSequencing, 0);

            } else {
                return (SearcherOutcome.UnknownError, 0);
            }

        } catch {
            return (SearcherOutcome.CallReverted, 0);
        }
    }
}

contract CallExecution is BitStuff {
    using CallChain for SearcherProof;

    address immutable internal _escrow;

    constructor(address escrow) {
        _escrow = escrow;
    }

    // TODO: this would be the FastLane address - fill in. 
    address constant public FEE_RECIPIENT = address(0); 

    function callStagingWrapper(
        SearcherProof memory proof,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external payable returns (bytes memory stagingData) {
        // This must be called by the escrow contract to make sure the locks cant
        // be tampered with

        require(msg.sender == _escrow, "ERR-DCW00 InvalidSenderStaging");
        
        bytes memory data = bytes.concat(stagingCall.stagingSelector, userCallData);

        proof.prove(stagingCall.stagingTo, data, false);

        bool callSuccess;
        (callSuccess, stagingData) = stagingCall.stagingTo.call{
            value: _fwdValueStaging(stagingCall.callConfig) ? msg.value : 0 // if staging explicitly needs tx.value, handler doesn't forward it
        }(
            data
        );
        require(callSuccess, "ERR-H02 CallStaging");
    }

    function delegateStagingWrapper(
        SearcherProof memory proof,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData) {
        // This must be called by the escrow contract to make sure the locks cant
        // be tampered with
        require(msg.sender == _escrow, "ERR-DCW00 InvalidSenderStaging");

        bytes memory data = bytes.concat(stagingCall.stagingSelector, userCallData);

        proof.prove(stagingCall.stagingTo, data, true);

        bool callSuccess;
        (callSuccess, stagingData) = stagingCall.stagingTo.delegatecall(
            bytes.concat(stagingCall.stagingSelector, userCallData)
        );
        require(callSuccess, "ERR-DCW01 DelegateStaging");
    }

    function callUserWrapper(
        SearcherProof memory proof,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData) {
        // This must be called by the escrow contract to make sure the locks cant
        // be tampered with

        require(msg.sender == _escrow, "ERR-DCW00 InvalidSenderStaging");

        proof.prove(userCall.from, userCall.data, false);

        bool callSuccess;
        (callSuccess, userReturnData) = userCall.to.call{
            value: userCall.value,
            gas: userCall.gas
        }(userCall.data);
        require(callSuccess, "ERR-03 UserCall");
    }

    function delegateUserWrapper(
        SearcherProof memory proof,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData) {
        // This must be called by the escrow contract to make sure the locks cant
        // be tampered with

        require(msg.sender == _escrow, "ERR-DCW00 InvalidSenderStaging");

        proof.prove(userCall.from, userCall.data, true);

        bool callSuccess;
        (callSuccess, userReturnData) = userCall.to.delegatecall{
            // NOTE: no value forwarding for delegatecall
            gas: userCall.gas
        }(userCall.data);
        require(callSuccess, "ERR-03 UserCall");
    }

    function callVerificationWrapper(
        StagingCall calldata stagingCall,
        bytes memory stagingData, 
        bytes memory userReturnData
    ) external {
        // This must be called by the escrow contract to make sure the locks cant
        // be tampered with.
        // NOTE: stagingData is the returned data from the staging call.
        // NOTE: userReturnData is the returned data from the user call
        require(msg.sender == _escrow, "ERR-DCW02 InvalidSenderVerification");

        bool callSuccess;
        (callSuccess,) = stagingCall.verificationTo.call{
            // if verification explicitly needs tx.value, handler doesn't forward it
            value: _fwdValueVerification(stagingCall.callConfig) ? address(this).balance : 0 
        }(
            abi.encodeWithSelector(stagingCall.verificationSelector, stagingData, userReturnData)
        );
        require(callSuccess, "ERR-07 CallVerification");
    }

    function delegateVerificationWrapper(
        StagingCall calldata stagingCall,
        bytes memory stagingData, 
        bytes memory userReturnData
    ) external {
        // This must be called by the escrow contract to make sure the locks cant
        // be tampered with.
        // NOTE: stagingData is the returned data from the staging call.
        require(msg.sender == _escrow, "ERR-DCW02 InvalidSenderVerification");

        bool callSuccess;
        (callSuccess,) = stagingCall.verificationTo.delegatecall(
            abi.encodeWithSelector(stagingCall.verificationSelector, stagingData, userReturnData)
        );
        require(callSuccess, "ERR-DCW03 DelegateVerification");
    }

    function searcherMetaTryCatch(
        SearcherProof memory proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external returns (uint256 searcherValueTransfer) {

        // Verify that it's the escrow contract calling
        require(msg.sender == _escrow, "ERR-04 InvalidCaller");
        require(
            address(this).balance == searcherCall.metaTx.value,
            "ERR-05 IncorrectValue"
        );

        // Searcher may pay the msg.value back to the Escrow contract directly
        uint256 escrowEtherBalance = _escrow.balance;

        // Initiate a memory array to track balances to measure if the
        // bid amount is paid.
        uint256[] memory tokenBalances = new uint[](searcherCall.bids.length);
        uint256 i;
        for (; i < searcherCall.bids.length;) {

            // Ether balance
            if (searcherCall.bids[i].token == address(0)) {
                tokenBalances[i] = address(this).balance;  // NOTE: this is the meta tx value

            // ERC20 balance
            } else {
                tokenBalances[i] = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
            }
            unchecked {++i;}
        }

          ////////////////////////////
         // SEARCHER SAFETY CHECKS //
        ////////////////////////////

        // Verify that the searcher's view of the user's calldata hasn't been altered
        // NOTE: Technically this check is redundant since the user's calldata is in the
        // searcher hash chain as verified below.
        require(proof.userCallHash == searcherCall.metaTx.userCallHash, ALTERED_USER_HASH);

        // Verify that the searcher's calldata is unaltered and being executed in the correct order
        // NOTE: This is NOT meant to protect the searcher's smart contract - it can be accessed with
        // copied versions of this data via delegatecall and therefore requires other protection.
        // The purpose of this is to ensure that the searcher doesn't have to trust the FastLane relay, 
        // the protocol frontend, or the user.
        proof.prove(searcherCall.metaTx.from, searcherCall.metaTx.data, false);

        // Execute the searcher call. 
        (bool success,) = ISearcherContract(searcherCall.metaTx.to).metaFlashCall{
            gas: gasLimit, 
            value: searcherCall.metaTx.value
        }(
            searcherCall.metaTx.from,
            searcherCall.metaTx.data,
            searcherCall.bids
        );

        // Verify that it was successful
        require(success, SEARCHER_CALL_REVERTED);

        // Get the value delta from the escrow contract
        // NOTE: reverting on underflow here is intended behavior
        escrowEtherBalance -= _escrow.balance;

        // Verify that the searcher repaid their msg.value
        require(address(this).balance + escrowEtherBalance >= searcherCall.metaTx.value, SEARCHER_MSG_VALUE_UNPAID);

        // Verify that the searcher paid what they bid
        bool etherIsBidToken;
        i = 0;
        uint256 balance;
        for (; i < searcherCall.bids.length;) {
            
            if (searcherCall.bids[i].token == address(0)) {

                etherIsBidToken = true;

                // First, verify that the bid was paid
                require(
                    address(this).balance + escrowEtherBalance >= tokenBalances[i] + searcherCall.bids[i].bidAmount,
                    SEARCHER_MSG_VALUE_UNPAID 
                    // TODO: differentiate errors between value not being paid back
                    // and a bid not being met.
                );
                
                // Check if the the execution environment owes the escrow Ether.     
                if (address(this).balance > tokenBalances[i] + searcherCall.bids[i].bidAmount) {
                    // Send the excess back to the escrow since the searcher
                    // may have flash borrowed from the contract

                    searcherValueTransfer = 
                        address(this).balance - (tokenBalances[i] + searcherCall.bids[i].bidAmount);
                    
                    SafeTransferLib.safeTransferETH(
                        _escrow, 
                        searcherValueTransfer
                    );

                    searcherValueTransfer = 0; // Set to 0 so that none is transferred back

                // Need to transfer Ether from escrow to this contract to pay the bids
                } else {
                    searcherValueTransfer = 
                        (tokenBalances[i] + searcherCall.bids[i].bidAmount) - address(this).balance;
                }

            } else {
                balance = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
                // First, verify that the bid was paid
                require(
                    balance >= tokenBalances[i] + searcherCall.bids[i].bidAmount,
                    SEARCHER_BID_UNPAID
                );
            }

            unchecked { ++i; }
        }
        
        // Handle Ether balances for case in which Ether is not a bid token
        if (!etherIsBidToken) {
            SafeTransferLib.safeTransferETH(
                _escrow, 
                address(this).balance
            );
        }
    }

    function disbursePayments(
        uint256 protocolShare,
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) external {
        // NOTE: the relay/frontend will verify that the bid 
        // and payments arrays are aligned
        // NOTE: pour one out for the eth mainnet homies
        // that'll need to keep their payee array short :(
        
        require(msg.sender == _escrow, "ERR-04 InvalidCaller");
        // declare some vars to make this trainwreck less unreadable
        PaymentData memory pmtData;
        // ERC20 token;
        address tokenAddress;
        uint256 payment;
        uint256 bidAmount;
        uint256 remainder;
        bool callSuccess;

        uint256 i;
        uint256 k;        

        for (; i < bids.length;) {
            tokenAddress = bids[i].token;
            bidAmount = bids[i].bidAmount;
            remainder = bidAmount;

            for (; k < payeeData[i].payments.length;) {

                pmtData = payeeData[i].payments[k];
                
                payment = bidAmount * pmtData.payeePercent / (100 + protocolShare);
                remainder -= payment;

                if (pmtData.pmtSelector != bytes4(0)) {
                    // TODO: handle native token / ETH
                    SafeTransferLib.safeTransfer(ERC20(tokenAddress), pmtData.payee, payment);
                
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
                SafeTransferLib.safeTransfer(ERC20(tokenAddress), FEE_RECIPIENT, remainder);

                unchecked{ ++k;}
            }

            unchecked{ ++i;}
        }
    }
}
