//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import { CallBits } from "../libraries/CallBits.sol";

import "../types/CallTypes.sol";
import "../types/GovernanceTypes.sol";
import { Verification } from "../types/VerificationTypes.sol";


import { ProtocolIntegration } from "./ProtocolIntegration.sol";

// This contract exists so that protocol frontends can sign and confirm the
// calldata for users.  Users already trust the frontends to build and verify
// their calldata.  This allows users to know that any CallData sourced via
// an external relay (such as FastLane) has been verified by the already-trusted
// frontend
contract ProtocolVerifier is EIP712, ProtocolIntegration {
    using ECDSA for bytes32;
    using CallBits for uint16;

    bytes32 constant public PROTOCOL_TYPE_HASH = keccak256(
        "ProtocolProof(address from,address to,uint256 nonce,uint256 deadline,bytes32 protocolDataHash,bytes32 callChainHash)"
    );

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
        ProtocolCall calldata protocolCall,
        Verification calldata verification
    ) internal returns (bool) {

        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up protocol nonces
        require(_verifySignature(verification), "ERR-PV01 InvalidSignature");

        // NOTE: to avoid replay attacks arising from key management errors,
        // the state changes below must be *saved* even if they render the 
        // transaction invalid. 
        // TODO: consider protocol-owned gas escrow.  Enshrined account 
        // abstraction may render that redundant at a large scale, but
        // allocating different parts of the tx to different parties
        // will allow for optimized trustlessness. This could lead to 
        // users not having to trust the front end at all - a huge 
        // improvement over the current experience.

        ApproverSigningData memory signatory = signatories[verification.proof.from];

        // generate the signing key
        bytes32 signingKey = keccak256(abi.encode(
            verification.proof.from,
            verification.proof.nonce
        ));

        // make sure this nonce hasn't already been used by this sender
        if (signatureTrackingMap[signingKey] != bytes32(0)) {
            return (false);
        }
        signatureTrackingMap[signingKey] = keccak256(verification.signature);

        // Make sure the signer is currently enabled by protocol owner
        // NOTE: check must occur after storing signature to prevent replays
        if (!signatory.enabled) {
            return (false);
        }

        // Verify that the protocol is onboarded and that the call config is 
        // genuine.
        bytes32 key = keccak256(
            abi.encode(
                protocolCall.to, 
                userCallTo, 
                signatory.governance,
                protocolCall.callConfig
            )
        );

        // NOTE: This check does not work if ProtocolControl is a proxy contract.
        // To avoid exposure to social engineering vulnerabilities, disgruntled 
        // former employees, or beneficiary uncertainty during intra-DAO conflict, 
        // governance should refrain from using a proxy contract for ProtocolControl. 
        bytes32 controlCodeHash = protocolCall.to.codehash;
        if (controlCodeHash == bytes32(0) || protocols[key] != controlCodeHash) {
            return (false);
        }

        // if the protocol indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in 
        // which builders or validators may be able to profit via censorship.
        // Protocols are encouraged to rely on the deadline parameter 
        // to prevent replay attacks. 
        if (protocolCall.callConfig.needsSequencedNonces()) {
            if (verification.proof.nonce != signatory.nonce + 1) {
                return (false);
            }
            unchecked { ++signatories[verification.proof.from].nonce;}
        
        // If not sequenced, check to see if this nonce is highest and store
        // it if so.  This ensures nonce + 1 will always be available. 
        } else {
            if (verification.proof.nonce > signatory.nonce + 1) {
                signatories[verification.proof.from].nonce = uint64(verification.proof.nonce) + 1;
            
            } else {
                unchecked { ++signatories[verification.proof.from].nonce;}
            }
        }
    
        return (true);
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
                    verification.proof.userCallHash,
                    verification.proof.callChainHash
                )
            )
        ).recover(verification.signature);
        
        return signer == verification.proof.from;
    }
}