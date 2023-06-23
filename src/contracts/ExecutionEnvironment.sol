//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IEscrow } from "../interfaces/IEscrow.sol";
import { ISafetyChecks } from "../interfaces/ISafetyChecks.sol";

import { SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import { CallExecution, CallChain } from "./CallExecution.sol";
import { BitStuff } from "./BitStuff.sol"; 

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall,
    CallConfig,
    SearcherOutcome,
    BidData,
    PaymentData,
    SearcherProof
} from "../libraries/DataTypes.sol";

contract ExecutionEnvironment is CallExecution {
    using CallChain for SearcherProof;

    address immutable internal _factory;
    address immutable internal _escrow;
    uint256 immutable internal _protocolShare;
    bool immutable internal _dirty; 

    // NOTE: If _dirty is true, that means contract has untrustworthy storage
    // because it not selfdestructed() on each go. 

    constructor(
        bool isDirty,
        uint16 protocolShare, 
        address escrow
    ) CallExecution(escrow) {
        _factory = msg.sender; 
        _escrow = escrow;
        _dirty = isDirty;
        _protocolShare = uint256(protocolShare);

        // Unless otherwise specified, this is meant to be a single-shot 
        // execution environment.
        // NOTE: selfdestruct will work post EIP-6780 as long as
        // it's called in the same transaction as contract creation
        if (!_dirty) {
            selfdestruct(payable(_factory));
        }
    } 

    function protoCall( 
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external 
        payable 
        returns (bytes32 userCallHash, bytes32 searcherChainHash) 
    {
        // Make sure it's the factory calling or a dirty storage contract
        require(_dirty || msg.sender == _factory, "ERR-H00 InvalidSender");

        // if there's any lingering eth balance, forward it to escrow
        if(address(this).balance - msg.value != 0) {
            // forward any surplus msg.value to the escrow for tracking
            // and eventual reimbursement to user (after searcher txs)
            // are finished processing
            SafeTransferLib.safeTransferETH(
                _escrow, 
                address(this).balance - msg.value
            );
        }

        // get the hash of the userCallData for future verification purposes
        userCallHash = keccak256(abi.encodePacked(userCall.to, userCall.data));

        // build a memory array to later verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index
        // order is:
        //      0: stagingCall
        //      1: userCall + keccak of prior
        //      2 to n: searcherCalls + keccak of prior
        // NOTE: if the staging call is skipped, the userCall has the 0 index.
        bytes32[] memory executionHashChain = _buildExecutionHashChain(
            stagingCall,
            userCall,
            searcherCalls
        );

        // Set the final hash in the searcher chain as the return value
        // so that the protocol can verify the match
        searcherChainHash = executionHashChain[executionHashChain.length-1];

        // declare some variables
        uint256 executionIndex; // tracks the index of executionHashChain array for calldata verification
        bytes memory stagingData; // capture any pre-execution state variables the protocol may need
        bytes memory userReturnData; // capture any user-returned values the protocol may need

        // Build hash chain for sequence verification
        SearcherProof memory proof = SearcherProof({
            previousHash: bytes32(0),
            targetHash: executionHashChain[executionIndex],
            userCallHash: userCallHash,
            index: executionIndex++
        });

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
        stagingData = IEscrow(_escrow).executeStagingCall(
            proof,
            stagingCall,
            userCall.data
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

        userReturnData = IEscrow(_escrow).executeUserCall(
            proof,
            stagingCall.callConfig,
            userCall
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

        // init some vars for the searcher loop
        uint256 gasWaterMark = gasleft();
        uint256 i; // init at 0
        bool auctionAlreadyWon = false;

        for (; i < searcherCalls.length;) {

            proof = proof.next(executionHashChain);

            if (
                IEscrow(_escrow).executeSearcherCall(
                    proof,
                    gasWaterMark,
                    auctionAlreadyWon,
                    searcherCalls[i]
                ) && !auctionAlreadyWon
            ) {
                // If this is first successful call, issue payments
                IEscrow(_escrow).executePayments(
                    _protocolShare,
                    searcherCalls[i].bids,
                    payeeData
                );
                auctionAlreadyWon = true;
            }
            
            gasWaterMark = gasleft();
            unchecked { ++i; }
        }

        // ###########  END SEARCHER EXECUTION #############
        // ---------------------------------------------
        // #########  BEGIN VERIFICATION EXECUTION ##########

        // Run a post-searcher verification check with the data from the staging call 
        // and the user's return data.
        ISafetyChecks(_escrow).handleVerification(
            stagingCall,
            stagingData,
            userReturnData
        );

        // #########  END VERIFICATION EXECUTION ##########
    }

    function _buildExecutionHashChain(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) internal pure returns (bytes32[] memory) {
        // build a memory array of hashes to verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index
        // order is:
        //      0: stagingCall
        //      1: userCall + keccak of prior
        //      2 to n: searcherCalls + keccak of prior
        // NOTE: if the staging call is skipped, the userCall has the 0 index.

        // memory array 
        // NOTE: memory arrays are not accessible by delegatecall. This is a key
        // security feature. Please alert me if this is untrue. 
        bytes32[] memory executionHashChain = new bytes32[](searcherCalls.length + 2);
        uint256 i; // array index
        
        bool needsStaging = _needsStaging(stagingCall.callConfig);

        // Use null bytes if staging is skipped, otherwise use actual. 
        bytes memory stagingBytes; 
        if (needsStaging) {
            stagingBytes = bytes.concat(stagingCall.stagingSelector, userCall.data);
        }
        
        // Start with staging call
        // NOTE: If staging is skipped, use empty bytes as calldata placeholder
        executionHashChain[0] = keccak256(
            abi.encodePacked(
                bytes32(0), // initial hash = null
                stagingCall.stagingTo,
                stagingBytes,
                needsStaging ? _delegateStaging(stagingCall.callConfig) : false, 
                i++
            )
        );
        
        // then user call
        executionHashChain[1] = keccak256(
            abi.encodePacked(
                executionHashChain[0], // always reference previous hash
                userCall.from,
                userCall.data,
                _delegateUser(stagingCall.callConfig),
                i++
            )
        );
        
        // i = 2 when starting searcher loop
        for (; i < executionHashChain.length;) {
            executionHashChain[i] = keccak256(
                abi.encodePacked(
                    executionHashChain[i-1], // reference previous hash
                    searcherCalls[i-2].metaTx.from, // searcher smart contract
                    searcherCalls[i-2].metaTx.data, // searcher calls start at 2
                    false, // searchers wont have access to delegatecall
                    i++
                )
            );
        }

        return executionHashChain;
    }

    receive() external payable {}

    fallback() external payable {}

}
