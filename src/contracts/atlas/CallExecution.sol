//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISearcherContract } from "../interfaces/ISearcherContract.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { ICallExecution } from "../interfaces/ICallExecution.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { FastLaneErrorsEvents } from "./Emissions.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";
import { ExecutionControl } from "../libraries/ExecutionControl.sol";

contract CallExecution is FastLaneErrorsEvents {
    using CallVerification for CallChainProof;

    uint256 constant public ATLAS_SHARE = 5; // TODO: this would be the FastLane address - fill in. 
    address constant public ATLAS_RECIPIENT = address(0); 

    address immutable public user;
    address immutable public escrow;
    address immutable public factory;

    constructor(address _user, address _escrow, address _factory) {
        user = _user;
        escrow = _escrow;
        factory = _factory;
    }

    function stagingWrapper(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) external returns (bytes memory stagingData) {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment
        require(msg.sender == escrow, "ERR-CE00 InvalidSenderStaging");

        stagingData = ExecutionControl.stage(proof, protocolCall, userCall);

    }

    function userWrapper(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData) {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment
        require(msg.sender == escrow, "ERR-CE00 InvalidSenderStaging");

        userReturnData = ExecutionControl.user(proof, protocolCall, stagingReturnData, userCall);
    }

    function verificationWrapper(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData, 
        bytes memory userReturnData
    ) external {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment
        require(msg.sender == escrow, "ERR-CE00 InvalidSenderStaging");

        ExecutionControl.verify(proof, protocolCall, stagingReturnData, userReturnData);
    }


    function searcherMetaTryCatch(
        CallChainProof memory proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment
        require(msg.sender == escrow, "ERR-04 InvalidCaller");
        require(
            address(this).balance == searcherCall.metaTx.value,
            "ERR-CE05 IncorrectValue"
        );

        // Searcher may pay the msg.value back to the Escrow contract directly
        uint256 escrowEtherBalance = escrow.balance;

        // track token balances to measure if the bid amount is paid.
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

        require(ISafetyLocks(escrow).confirmSafetyCallback(), SEARCHER_FAILED_CALLBACK);

        // Get the value delta from the escrow contract
        // NOTE: reverting on underflow here is intended behavior since the ExecutionEnvironment address
        // should have 0 value. 
        uint256 escrowBalanceDelta = escrowEtherBalance - escrow.balance;

        // Verify that the searcher repaid their msg.value
        require(escrowBalanceDelta >= searcherCall.metaTx.value, SEARCHER_MSG_VALUE_UNPAID);

        // Verify that the searcher paid what they bid
        bool etherIsBidToken;
        i = 0;
        uint256 balance;

        for (; i < searcherCall.bids.length;) {
            
            // ERC20 tokens as bid currency
            if (!(searcherCall.bids[i].token == address(0))) {

                balance = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
                // First, verify that the bid was paid
                require(
                    balance >= tokenBalances[i] + searcherCall.bids[i].bidAmount,
                    SEARCHER_BID_UNPAID
                );
            

            // Native Gas (Ether) as bid currency
            } else {
                etherIsBidToken = true;

                balance = address(this).balance;
                
                // First, verify that the bid was paid
                require(
                    balance >= searcherCall.bids[i].bidAmount, // tokenBalances[i] = 0 for ether
                    SEARCHER_BID_UNPAID 
                );
                
                // TODO: Logic to check if the the execution environment owes the escrow Ether.     

                tokenBalances[i] = balance; 
            }

            unchecked { ++i; }
        }
    }

    function allocateRewards(
        ProtocolCall calldata protocolCall,
        BidData[] memory bids, // Converted to memory
        PayeeData[] calldata payeeData
    ) external {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment
        require(msg.sender == escrow, "ERR-04 InvalidCaller");

        uint256 totalEtherReward;
        uint256 payment;
        uint256 i;      

        for (; i < bids.length;) {

            payment = (bids[i].bidAmount * ATLAS_SHARE) / 100;

            if (bids[i].token != address(0)) {
                SafeTransferLib.safeTransfer(ERC20(bids[i].token), ATLAS_RECIPIENT, payment);
                totalEtherReward = bids[i].bidAmount - payment; // NOTE: This is transferred to protocolControl as msg.value
            
            } else {
                SafeTransferLib.safeTransferETH(ATLAS_RECIPIENT, payment);
            }

            bids[i].bidAmount -= payment;

            unchecked{ ++i;}
        }

        ExecutionControl.allocate(protocolCall, totalEtherReward, bids, payeeData);
    }
}
