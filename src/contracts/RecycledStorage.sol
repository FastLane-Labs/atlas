//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

contract RecycledStorage is ExecutionEnvironment {

    // This contract is meant as a simple but untrusted implementation
    // of a way to use delegatecall.  If one of the approved protocols
    // allows an attack vector, this entire contract will be at risk. 

    // Expect this contract to be self-destructed and redeployed any time
    // a partnered protocol is exposed. Do not store value here, do not count
    // on locks, and be prepared to redeploy the contract should it be destroyed.

    // Do not trust ANY storage here, this is a DIRTY sandbox and anyone calling
    // this should expect any interaction with storage to be adversarial

    // Most importantly of all, do not trust ANY calls *originating* from 
    // this address.

    constructor(
        uint256 _protocolShare, 
        address _escrow
    ) ExecutionEnvironment(msg.sender, _escrow, true, _protocolShare) {}

    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable {
        // build a memory array to later verify execution ordering. Each bytes32 
        // is the hash of the calldata, a bool representing if its a delegatecall
        // or standard call, and a uint256 representing its execution index
        // order is:
        //      0: stagingCall
        //      1: userCall + keccak of prior
        //      2 to n: searcherCalls + keccak of prior
        // NOTE: if the staging call is skipped, the userCall has the 0 index.
        bytes32[] memory executionHashChain = CallVerification.buildExecutionHashChain(
            protocolCall,
            userCall,
            searcherCalls
        );

        /// Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        if (
            !IAtlas(_factory).untrustedVerifyProtocol(
                userCall.to,
                searcherCalls.length,
                protocolCall,
                verification
            )
        ) { return; }

        // Signature / hashing failures past this point can be safely reverted.
        // This is because those reverts are caused by invalid signatures or 
        // altered calldata, both of which are keys in the protocol's signature
        // and which will *always* fail, making replay attacks impossible. 

        // Check that the value of the tx is greater than or equal to the value specified
        // NOTE: a msg.value *higher* than user value could be used by the staging call.
        // There is a further check in the handler before the usercall to verify. 
        require(msg.value >= userCall.value, "ERR-DS03 ValueExceedsBalance");
        require(searcherCalls.length < type(uint8).max -1, "ERR-DS02 TooManySearcherCalls");
        require(block.number <= userCall.deadline, "ERR-DS03 DeadlineExceeded");


        // delegatecall from this first level will preserve msg.sender but prevents
        // us from trusting *any* of the storage
        (bool callSuccess, bytes memory data) = address(this).delegatecall(
            abi.encodeWithSelector(
                ExecutionEnvironment.protoCall.selector, 
                protocolCall,
                userCall,
                payeeData,
                searcherCalls,
                executionHashChain
            )
        );
        require(callSuccess, "ERR-F10 DelegateCallFail");
        CallChainProof memory proof = abi.decode(
            data, (CallChainProof)
        );

        // Verify that the frontend's view of the searchers' signed calldata was unaltered by user
        require(
            executionHashChain[executionHashChain.length-2] == verification.proof.callChainHash, "ERR-F05 UserCallAltered"
        );

        // Verify that the execution system's sequencing of the transaction calldata was unaltered by searchers
        // NOTE: This functions as an "exploit prevention mechanism" as the contract itself already verifies trustless
        // execution. 
        require(
            proof.previousHash == verification.proof.callChainHash, "ERR-F05 SearcherExploitDetected"
        );

        // Release the locks
        IAtlas(_factory).untrustedReleaseLock(proof.previousHash);
    }
}