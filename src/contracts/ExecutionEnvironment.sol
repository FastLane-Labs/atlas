//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IEscrow } from "../interfaces/IEscrow.sol";

import { SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import { CallExecution } from "./CallExecution.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

contract ExecutionEnvironment is CallExecution {
    using CallVerification for CallChainProof;
    using CallVerification for bytes32[];

    address immutable public control;
    uint16 immutable public config;

    constructor(
        address _user,
        address _escrow,
        address _factory,
        address _protocolControl,
        uint16 _callConfig
    ) CallExecution(_user, _escrow, _factory) {
        control = _protocolControl;
        config = _callConfig;
    } 

    function protoCall( 
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        bytes32[] calldata executionHashChain // calculated by msg.sender (Factory)
    ) external payable returns (CallChainProof memory) { 
        return _protoCall(
            protocolCall,
            userCall,
            payeeData,
            searcherCalls,
            executionHashChain
        );
    }

    function _protoCall( 
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, 
        SearcherCall[] calldata searcherCalls, 
        bytes32[] memory executionHashChain 
    ) internal validSender(protocolCall, userCall) 
        returns (CallChainProof memory proof) 
    {
        // Initialize proof for executionHashChain for sequence verification
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
        bytes memory stagingReturnData = IEscrow(escrow).executeStagingCall(
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

        bytes memory userReturnData = IEscrow(escrow).executeUserCall(
            proof,
            protocolCall,
            stagingReturnData,
            userCall
        );
        
        // forward any surplus msg.value to the escrow for tracking
        // and eventual reimbursement to user (after searcher txs)
        // are finished processing
        if (address(this).balance != 0) {
            SafeTransferLib.safeTransferETH(
                escrow, 
                address(this).balance
            );
        }

        // ###########  END USER EXECUTION #############
        // ---------------------------------------------
        // #########  BEGIN SEARCHER EXECUTION ##########

        _iterateSearchers(
            protocolCall,
            payeeData,
            searcherCalls,
            executionHashChain
        );

        // ###########  END SEARCHER EXECUTION #############
        // ---------------------------------------------
        // #########  BEGIN VERIFICATION EXECUTION ##########

        // Run a post-searcher verification check with the data from the staging call 
        // and the user's return data.
        // Build the final proof now that we know its input data
        proof = proof.addVerificationCallProof(
            protocolCall.to,
            CallVerification.delegateVerification(protocolCall.callConfig),
            stagingReturnData,
            userReturnData
        );

        IEscrow(escrow).executeVerificationCall(
            proof,
            protocolCall,
            stagingReturnData,
            userReturnData
        );

        // #########  END VERIFICATION EXECUTION ##########
    }

    function _iterateSearchers(
        ProtocolCall calldata protocolCall,
        PayeeData[] calldata payeeData,
        SearcherCall[] calldata searcherCalls,
        bytes32[] memory executionHashChain
    ) internal returns (CallChainProof memory proof) {
        uint256 i; // init at 0
        bool auctionAlreadyWon = false;
        uint256 gasWaterMark;

        for (; i < searcherCalls.length;) {

            gasWaterMark = gasleft();

            proof = proof.next(executionHashChain);

            if (
                IEscrow(escrow).executeSearcherCall(
                    proof,
                    gasWaterMark,
                    auctionAlreadyWon,
                    searcherCalls[i]
                )
            ) {
                if (!auctionAlreadyWon) {
                    auctionAlreadyWon = true;
                    _handlePayments(protocolCall, searcherCalls[i].bids, payeeData);
                }
            }
            unchecked { ++i; }
        }
    }

    function _handlePayments(
        ProtocolCall calldata protocolCall,
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) internal {
        // If this is first successful call, issue payments
        IEscrow(escrow).executePayments(
            protocolCall,
            bids,
            payeeData
        );
    }

    modifier validSender(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall
    ) {
        require(userCall.from == user, "ERR-EE01 InvalidUser");
        require(protocolCall.to == control, "ERR-EE02 InvalidControl");
        require(protocolCall.callConfig == config, "ERR-EE03 InvalidConfig");
        require(msg.sender == factory || msg.sender == user, "ERR-EE04 InvalidSender");
        require(tx.origin == user, "ERR-EE05 InvalidOrigin");
        _;
    }

    receive() external payable {}

    fallback() external payable {}

}
