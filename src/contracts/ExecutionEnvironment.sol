//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IEscrow } from "../interfaces/IEscrow.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import { SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import { CallExecution } from "./CallExecution.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

contract ExecutionEnvironment is CallExecution {
    using CallVerification for CallChainProof;
    using CallVerification for bytes32[];

    address immutable internal _factory;

    bool immutable internal _dirty; 

    // NOTE: If _dirty is true, that means contract has untrustworthy storage
    // because it not selfdestructed() on each go. 

    constructor(
        bool isRecycled,
        uint256 protocolShare,

        address escrow
    ) CallExecution(escrow, address(0), protocolShare) {
        _factory = msg.sender; 
        _dirty = isRecycled;

        // Unless otherwise specified, this is meant to be a single-shot 
        // execution environment.
        // NOTE: selfdestruct will work post EIP-6780 as long as
        // it's called in the same transaction as contract creation
        
        // COMMENTED OUT FOR TEST PURPOSES
        //if (!_dirty) {
        //    selfdestruct(payable(_factory));
        //}
    } 

    function protoCall( 
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        bytes32[] memory executionHashChain // calculated by msg.sender (Factory)
    ) external 
        payable 
        returns (CallChainProof memory proof) 
    {
        // Make sure it's the factory calling or a dirty storage contract
        require(_dirty || msg.sender == _factory, "ERR-H00 InvalidSender");

        // Build initialize proof for executionHashChain for sequence verification
        proof = CallVerification.initializeProof(
            keccak256(abi.encodePacked(userCall.to, userCall.data)), 
            executionHashChain
        );

        // ###########  END MEMORY PREPARATION #############
        // ---------------------------------------------
        // #########  BEGIN STAGING EXECUTION ##########

        // Stage the execution environment for the user, if necessary
        // This will ask the safety contract / escrow to activate its locks and then trigger the 
        // staging callback func in this in this contract. 
        // NOTE: this may be a trusted delegatecall if the protocol intends it to be, 
        // but this contract will have empty storage.
        // NOTE: the calldata for the staging call must be the user's calldata
        // NOTE: the staging contracts we're calling should be custom-made for each protocol and 
        // should be immutable.  If an update is required, a new one should be made. 
        bytes memory stagingReturnData = IEscrow(_escrow).executeStagingCall(
            proof,
            protocolCall,
            userCall
        );
        
        // ###########  END STAGING EXECUTION #############
        // ---------------------------------------------
        // #########  BEGIN USER EXECUTION ##########

        // Do the user's call. This will ask the safety contract / escrow to activate its locks and 
        // then trigger the user callback func in this in this contract.
        // NOTE: balance check is necessary due to the optionality for a different
        // msg.value to have been used during the staging call
        require(address(this).balance >= userCall.value, "ERR-H03 ValueExceedsBalance");

        proof = proof.next(executionHashChain);

        bytes memory userReturnData = IEscrow(_escrow).executeUserCall(
            proof,
            protocolCall,
            stagingReturnData,
            userCall
        );

        // Build the final proof now that we know its input data
        executionHashChain = executionHashChain.addVerificationCallProof(
            protocolCall.to,
            CallVerification.delegateVerification(protocolCall.callConfig),
            stagingReturnData,
            userReturnData
        );
        
        // forward any surplus msg.value to the escrow for tracking
        // and eventual reimbursement to user (after searcher txs)
        // are finished processing
        if (address(this).balance != 0) {
            SafeTransferLib.safeTransferETH(
                _escrow, 
                address(this).balance
            );
        }

        // ###########  END USER EXECUTION #############
        // ---------------------------------------------
        // #########  BEGIN SEARCHER EXECUTION ##########

        uint256 i; // init at 0
        bool auctionWon = false;

        for (; i < searcherCalls.length;) {

            proof = proof.next(executionHashChain);

            if (_iterateSearcher(proof, searcherCalls[i], auctionWon)) {
                if (!auctionWon) {
                    auctionWon = true;
                    _handlePayments(protocolCall, searcherCalls[i].bids, payeeData);
                }
            }
            unchecked { ++i; }
        }

        // ###########  END SEARCHER EXECUTION #############
        // ---------------------------------------------
        // #########  BEGIN VERIFICATION EXECUTION ##########

        // Run a post-searcher verification check with the data from the staging call 
        // and the user's return data.
        proof = proof.next(executionHashChain);

        IEscrow(_escrow).executeVerificationCall(
            proof,
            protocolCall,
            stagingReturnData,
            userReturnData
        );

        // #########  END VERIFICATION EXECUTION ##########
    }

    function _iterateSearcher(
        CallChainProof memory proof,
        SearcherCall calldata searcherCall,
        bool auctionAlreadyWon
    ) internal returns (bool) {
        uint256 gasWaterMark = gasleft();

        if (
            IEscrow(_escrow).executeSearcherCall(
                proof,
                gasWaterMark,
                auctionAlreadyWon,
                searcherCall
            ) && !auctionAlreadyWon
        ) {
            
            auctionAlreadyWon = true;
        }
        return auctionAlreadyWon;
    }

    function _handlePayments(
        ProtocolCall calldata protocolCall,
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) internal {
        // If this is first successful call, issue payments
        IEscrow(_escrow).executePayments(
            protocolCall,
            bids,
            payeeData
        );
    }

    receive() external payable {}

    fallback() external payable {}

}
