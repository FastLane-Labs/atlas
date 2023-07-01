//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

library CallVerification {
   
    function initializeProof(
        bytes32 userCallHash,
        bytes32 executionHashChainZeroIndex
    ) internal pure returns (CallChainProof memory) {
        return CallChainProof({
            previousHash: bytes32(0),
            targetHash: executionHashChainZeroIndex,
            userCallHash: userCallHash,
            index: 0
        });
    }

    function addVerificationCallProof(
        CallChainProof memory self,
        address to,
        bool isDelegated,
        bytes memory stagingReturnData,
        bytes memory userReturnData
    ) internal pure returns (CallChainProof memory) {
        self.previousHash = self.targetHash;
        self.targetHash = keccak256(
            abi.encodePacked(
                self.previousHash,
                to,
                abi.encodeWithSelector(
                    IProtocolControl.verificationCall.selector, 
                    stagingReturnData,
                    userReturnData
                ),
                isDelegated, 
                ++self.index
            )
        );
        return self;
    }

    function delegateVerification(uint16 callConfig) internal pure returns (bool) {
        return (callConfig & 1 << uint16(CallConfig.DelegateStaging) != 0);
    }

    function next(
        CallChainProof memory self, 
        bytes32[] memory executionHashChain
    ) internal pure returns (CallChainProof memory) 
    {
        self.previousHash = self.targetHash;
        self.targetHash = executionHashChain[++self.index];
        return self;
    }

    function prove(
        CallChainProof memory self, 
        address from, 
        bytes memory data, 
        bool isDelegated
    ) internal pure returns (bool) 
    {
        return self.targetHash == keccak256(
            abi.encodePacked(
                self.previousHash,
                from,
                data,
                isDelegated, 
                self.index
            )
        );
    }

    function buildExecutionHashChain(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall,
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) internal pure returns (bytes32[] memory executionHashChain) {
        // build a memory array of hashes to verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index
        // order is:
        //      0: stagingCall
        //      1: userCall + keccak of prior
        //      2 to n: searcherCalls + keccak of prior

        // memory array 
        // NOTE: memory arrays are not accessible by delegatecall. This is a key
        // security feature. 
        executionHashChain = new bytes32[](searcherCalls.length + 3);
        uint256 i; // array index
        
        // Start with staging call
        executionHashChain[0] = keccak256(
            abi.encodePacked(
                bytes32(0), // initial hash = null
                protocolCall.to,
                userCall.data,
                true, 
                i
            )
        );
        unchecked { ++i;}
        
        // then user call
        executionHashChain[1] = keccak256(
            abi.encodePacked(
                executionHashChain[0], // always reference previous hash
                userCall.from,
                userCall.data,
                delegateUser(protocolCall.callConfig),
                i
            )
        );
        unchecked { ++i;}
        
        // i = 2 when starting searcher loop
        for (; i < executionHashChain.length;) {
            executionHashChain[i] = keccak256(
                abi.encodePacked(
                    executionHashChain[i-1], // reference previous hash
                    searcherCalls[i-2].metaTx.from, // searcher smart contract
                    searcherCalls[i-2].metaTx.data, // searcher calls start at 2
                    false, // searchers wont have access to delegatecall
                    i
                )
            );
            unchecked { ++i;}
        }
        // NOTE: We do not have a way to confirm the verification input calldata
        // because it is dependent on the outcome of the staging and user calls
        // but it can be updated once those become known, which is AFTER the 
        // staging and user calls but BEFORE the searcher calls. 
    }

    function delegateUser(uint16 callConfig) internal pure returns (bool) {
        return (callConfig & 1 << uint16(CallConfig.DelegateUser) != 0);
    }
}



