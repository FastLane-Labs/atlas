//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

library CallVerification {
   
    function initializeProof(
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) internal pure returns (CallChainProof memory) {
        return CallChainProof({
            previousHash: bytes32(0),
            targetHash: keccak256(
                abi.encodePacked(
                    bytes32(0), // initial hash = null
                    protocolCall.to,
                    abi.encodeWithSelector(
                        IProtocolControl.stageCall.selector,
                        userCall.to, 
                        userCall.from, 
                        bytes4(userCall.data), 
                        userCall.data[4:]
                    ),
                    uint256(0)
                )
            ),
            index: 0
        });
    }

    function next(
        CallChainProof memory self, 
        address from,
        bytes calldata data
    ) internal pure returns (CallChainProof memory) 
    {
        self.previousHash = self.targetHash;
        self.targetHash = keccak256(
            abi.encodePacked(
                self.previousHash,
                from,
                data,
                ++self.index
            )
        );
        return self;
    }

    function proveCD(
        CallChainProof calldata self, 
        address from, 
        bytes calldata data
    ) internal pure returns (bool) 
    {
        return self.targetHash == keccak256(
            abi.encodePacked(
                self.previousHash,
                from,
                data,
                self.index
            )
        );
    }

    function prove(
        CallChainProof calldata self, 
        address from, 
        bytes memory data
    ) internal pure returns (bool) 
    {
        return self.targetHash == keccak256(
            abi.encodePacked(
                self.previousHash,
                from,
                data,
                self.index
            )
        );
    }

    function addVerificationCallProof(
        CallChainProof memory self,
        address to,
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
                ++self.index
            )
        );
        return self;
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
        executionHashChain = new bytes32[](searcherCalls.length + 2);
        uint256 i = 0; // array index
        
        // Start with staging call
        executionHashChain[0] = keccak256(
            abi.encodePacked(
                bytes32(0), // initial hash = null
                protocolCall.to,
                abi.encodeWithSelector(
                    IProtocolControl.stageCall.selector,
                    userCall.to, 
                    userCall.from, 
                    bytes4(userCall.data), 
                    userCall.data[4:]
                ),
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
}



