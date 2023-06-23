//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall,
    ProtocolData,
    Verification
} from "../libraries/DataTypes.sol";

contract SketchyStorageEnvironment is ExecutionEnvironment{

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

    address public immutable factory;
    address public immutable escrow;

    constructor(
        uint16 _protocolShare, 
        address _escrow
    ) ExecutionEnvironment(true, _protocolShare, _escrow) {
        factory = msg.sender;
        escrow = _escrow;
    }

    function metacall(
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall, // set by user
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        Verification calldata verification // supplied by front end after it sees the other data
    ) external payable {
        /// Verify that the calldata injection came from the protocol frontend
        // NOTE: fail result causes function to return rather than revert. 
        // This allows signature data to be stored, which helps prevent 
        // replay attacks.
        (bool invalidCall, ProtocolData memory protocolData) = IAtlas(factory).untrustedVerifyProtocol(
            verification, userCall.to
        );

        if (!invalidCall) {
            return;
        }
        // Signature / hashing failures past this point can be safely reverted.
        // This is because those reverts are caused by invalid signatures or 
        // altered calldata, both of which are keys in the protocol's signature
        // and which will *always* fail, making replay attacks impossible. 

        // Check that the value of the tx is greater than or equal to the value specified
        // NOTE: a msg.value *higher* than user value could be used by the staging call.
        // There is a further check in the handler before the usercall to verify. 
        require(msg.value >= userCall.value, "ERR-DS03 ValueExceedsBalance");
        require(protocolData.owner != address(0), "ERR-DS01 UnsuportedUserTo");
        require(searcherCalls.length < type(uint8).max -1, "ERR-DS02 TooManySearcherCalls");
        require(block.number <= userCall.deadline, "ERR-DS03 DeadlineExceeded");


        // delegatecall from this first level will preserve msg.sender but prevents
        // us from trusting *any* of the storage
        (bool callSuccess, bytes memory data) = address(this).delegatecall(
            abi.encodeWithSelector(
                ExecutionEnvironment.protoCall.selector, 
                stagingCall,
                userCall,
                payeeData,
                searcherCalls
            )
        );
        require(callSuccess, "ERR-F10 DelegateCallFail");
        (bytes32 userCallHash, bytes32 searcherChainHash) = abi.decode(
            data, (bytes32, bytes32)
        );

        // Verify that the frontend's view of the user's calldata is unaltered - presumably by user
        require(
            userCallHash == verification.proof.userCallHash, "ERR-F04 UserCallAltered"
        );

        // Verify that the frontend's view of the searchers' signed calldata was unaltered by user
        require(
            searcherChainHash == verification.proof.searcherChainHash, "ERR-F05 SearcherCallAltered"
        );

        // release the locks
        IAtlas(factory).untrustedReleaseLock(
            keccack256(
                userCallHash,
                verification.proof.protocolDataHash,
                searcherChainHash
            )
        );
    }
}