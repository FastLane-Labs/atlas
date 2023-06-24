//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;


import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {
    ProtocolData,
    ProtocolProof,
    Verification,
    PROTOCOL_TYPE_HASH
} from "../libraries/DataTypes.sol";

// This contract exists so that protocol frontends can sign and confirm the
// calldata for users.  Users already trust the frontends to build and verify
// their calldata.  This allows users to know that any CallData sourced via
// an external relay (such as FastLane) has been verified by the already-trusted
// frontend
contract ProtocolVerifier is EIP712 {
    using ECDSA for bytes32;

    /*
    struct ProtocolProof {
        address from;
        address to;
        uint256 nonce;
        uint256 deadline;
        bytes32 userCallHash; // keccak256 of userCall.to, userCall.data
        bytes32 protocolDataHash; // keccak256 of ProtocolData struct
        bytes32 callChainHash; // keccak256 of the searchers' txs
    }

    struct Verification {
        ProtocolProof proof;
        bytes signature;
    }
    */

    // map for tracking protocol owned EOAs and nonces
    // NOTE: protocols should have access to multiple EOAs
    // to allow for concurrent processing and to prevent
    // builder censorship.
    // NOTE: to prevent builder censorship, protocol nonces can be 
    // processed in any order so long as they arent duplicated and 
    // as long as the protocol opts in to it
    struct ApproverSigningData {
        address protocol; // userCall.to
        bool enabled; // EOA has been disabled if false
        bool sequenced; // if true, nonces must be processed in order
        uint64 nonce; // the highest nonce used so far. n+1 is always available
    }

    // map to load execution environment parameters for each protocol
    mapping(address => ProtocolData) public protocolDataMap;

    // map for tracking which EOAs are approved for a given protocol
    //     approver   userCall.to
    mapping(address => ApproverSigningData) public approvedAddressMap;
    
    // map for tracking usage of protocol-owned EOAs and signatures 
    //  keccak256(from, nonce) => keccak256(signature)
    mapping(bytes32 => bytes32) public signatureTrackingMap;

    constructor() EIP712("ProtoCallHandler", "0.0.1")  {}

    // Verify that the protocol's front end generated the staging
    // information and that it matches the on-chain data.  
    // Verify that the protocol's front end's data is based on
    // the data submitted by the user and by the searchers.
    // NOTE: the protocol's front end is the last party in 
    // the supply chain to submit data.  If any other party
    // (user, searcher, FastLane,  or a collusion between 
    // all of them) attempts to alter it, this check will fail
    function _verifyProtocol(
        address userCallTo,
        Verification calldata verification
    ) internal returns (bool, ProtocolData memory) {
        
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up protocol nonces
        require(_verifySignature(verification), "ERR-PV01 InvalidSignature");

        // Load protocol data for the user's targeted protocol
        ProtocolData memory protocolData = protocolDataMap[userCallTo];


        // NOTE: to avoid replay attacks arising from key management errors,
        // the state changes below must be *saved* even if they render the 
        // transaction invalid. 
        // TODO: consider protocol-owned gas escrow.  Enshrined account 
        // abstraction may render that redundant at a large scale, but
        // allocating different parts of the tx to different parties
        // will allow for optimized trustlessness. This could lead to 
        // users not having to trust the front end at all - a huge 
        // improvement over the current experience.

        ApproverSigningData memory approver = approvedAddressMap[verification.proof.from]; 

        // generate the signing key
        bytes32 signingKey = keccak256(abi.encode(
            verification.proof.from,
            verification.proof.nonce
        ));

        // make sure this nonce hasn't already been used by this sender
        if (signatureTrackingMap[signingKey] != bytes32(0)) {
            return (false, protocolData);
        }
        signatureTrackingMap[signingKey] = keccak256(verification.signature);

        // make sure the signer is currently enabled by protocol owner
        // NOTE: check must occur after storing signature to prevent replays
        if (!approver.enabled) {
            return (false, protocolData);
        }

        // if the protocol indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in 
        // which builders or validators may be able to profit via censorship
        // NOTE: protocols are encouraged to rely on the deadline parameter 
        // to prevent replay attacks. 
        if (approver.sequenced) {
            if (verification.proof.nonce != approver.nonce + 1) {
                return (false, protocolData);
            }
            unchecked { ++approvedAddressMap[verification.proof.from].nonce;}
        
        // If not sequenced, check to see if this nonce is highest and store
        // it if so.  This ensures nonce + 1 will always be available. 
        } else {
            if (verification.proof.nonce > approver.nonce + 1) {
                approvedAddressMap[verification.proof.from].nonce = uint64(verification.proof.nonce) + 1;
            
            } else {
                unchecked { ++approvedAddressMap[verification.proof.from].nonce;}
            }
        }

        // Verify that the submitted ProtocolData matches the ProtocolData 
        // submitted by the frontend. 
        // TODO: break struct to elements and use encode for backend simplicity?
        if (!(keccak256(abi.encode(protocolData)) == verification.proof.protocolDataHash)) {
            return (false, protocolData);
        }
    
        // TODO: consider putting userCallHash verification here
        return (true, protocolData);
    }

    // TODO: make a more thorough version of this
    function _verifySignature(
        Verification calldata verification
    ) internal view returns (bool) {
        
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    PROTOCOL_TYPE_HASH, 
                    verification.proof.from, 
                    verification.proof.to, 
                    verification.proof.nonce,
                    verification.proof.deadline,
                    verification.proof.protocolDataHash,
                    verification.proof.callChainHash
                )
            )
        ).recover(verification.signature);
        
        return signer == verification.proof.from;
    }

}