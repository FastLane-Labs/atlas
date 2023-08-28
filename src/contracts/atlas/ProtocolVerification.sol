//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/CallTypes.sol";
import "../types/GovernanceTypes.sol";

import {Verification, ProtocolProof} from "../types/VerificationTypes.sol";

import {ProtocolIntegration} from "./ProtocolIntegration.sol";

import "forge-std/Test.sol"; // TODO remove

// This contract exists so that protocol frontends can sign and confirm the
// calldata for users.  Users already trust the frontends to build and verify
// their calldata.  This allows users to know that any CallData sourced via
// an external relay (such as FastLane) has been verified by the already-trusted
// frontend
contract ProtocolVerifier is EIP712, ProtocolIntegration {
    using ECDSA for bytes32;
    using CallBits for uint16;

    bytes32 public constant PROTOCOL_TYPE_HASH = keccak256(
        "ProtocolProof(address from,address to,uint256 nonce,uint256 deadline,bytes32 userCallHash,bytes32 callChainHash,bytes32 controlCodeHash)"
    );

    bytes32 public constant USER_TYPE_HASH = keccak256(
        "UserMetaTx(address from,address to,uint256 deadline,uint256 gas,uint256 nonce,uint256 maxFeePerGas,uint256 value,address control,bytes32 data)"
    );

    mapping(address => uint256) public userNonces;
    
    struct NonceTracker {
        uint64 asyncFloor;
        uint64 asyncCeiling;
        uint64 blockingLast;
    }

    //  keccak256(from, callConfig, nonce) => to
    mapping(bytes32 => address) public asyncNonceFills;

    constructor() EIP712("ProtoCallHandler", "0.0.1") {}


    // 
    // PROTOCOL VERIFICATION
    //

    // Verify that the protocol's front end generated the staging
    // information and that it matches the on-chain data.
    // Verify that the protocol's front end's data is based on
    // the data submitted by the user and by the searchers.
    // NOTE: the protocol's front end is the last party in
    // the supply chain to submit data.  If any other party
    // (user, searcher, FastLane,  or a collusion between
    // all of them) attempts to alter it, this check will fail
    function _verifyProtocol(address userCallTo, ProtocolCall calldata protocolCall, Verification calldata verification)
        internal
        returns (bool)
    {
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up protocol nonces
        require(_verifyProtocolSignature(verification), "ERR-PV01 InvalidSignature");

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

        if (verification.proof.to != protocolCall.to) {
            return (false);
        }

        // Make sure the signer is currently enabled by protocol owner
        // NOTE: check must occur after storing signature to prevent replays
        if (!signatory.enabled) {
            return (false);
        }

        // Verify that the protocol is onboarded and that the call config is
        // genuine.
        bytes32 key = keccak256(abi.encode(protocolCall.to, userCallTo, signatory.governance, protocolCall.callConfig));

        // NOTE: This check does not work if ProtocolControl is a proxy contract.
        // To avoid exposure to social engineering vulnerabilities, disgruntled
        // former employees, or beneficiary uncertainty during intra-DAO conflict,
        // governance should refrain from using a proxy contract for ProtocolControl.
        if (protocolCall.to.codehash == bytes32(0) || protocols[key] != protocolCall.to.codehash) {
            return (false);
        }

        // Verify that ProtocolControl hasn't been updated.  
        // NOTE: Performing this check here allows the searchers' checks 
        // to be against the verification proof's controlCodeHash to save gas.
        if (protocolCall.to.codehash != verification.proof.controlCodeHash) {
            return (false);
        }

        if (verification.proof.nonce > type(uint64).max - 1) {
            return (false);
        }

        // If the protocol indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // Protocols are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (protocolCall.callConfig.needsSequencedNonces()) {
            if (verification.proof.nonce != signatory.nonce + 1) {
                return (false);
            }

            unchecked {++signatories[verification.proof.from].nonce;}
            
            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            // NOTE: including the callConfig in the asyncNonceKey should prevent
            // issues occuring when a protocol may switch configs between blocking 
            // and async, since callConfig can double as another seed. 
            bytes32 asyncNonceKey = keccak256(abi.encode(verification.proof.from, protocolCall.callConfig, verification.proof.nonce + 1));
            
            if (asyncNonceFills[asyncNonceKey] != address(0)) {
                return (false);
            }

            asyncNonceFills[asyncNonceKey] = protocolCall.to;
        }

        return (true);
    }

    function _getProofHash(ProtocolProof memory proof) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                PROTOCOL_TYPE_HASH,
                proof.from,
                proof.to,
                proof.nonce,
                proof.deadline,
                proof.userCallHash,
                proof.callChainHash,
                proof.controlCodeHash
            )
        );
    }

    function _verifyProtocolSignature(Verification calldata verification) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getProofHash(verification.proof)).recover(verification.signature);

        return signer == verification.proof.from;
        // return true;
    }

    function getVerificationPayload(Verification memory verification) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(verification.proof));
    }

    //
    // USER VERIFICATION
    //

    // Verify the user's meta transaction
    function _verifyUser(ProtocolCall calldata protocolCall, UserCall calldata userCall)
        internal
        returns (bool)
    {
        
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up protocol userNonces
        require(_verifyUserSignature(userCall), "ERR-UV01 InvalidSignature");

        if (userCall.metaTx.control != protocolCall.to) {
            return (false);
        }

        if (userCall.metaTx.nonce > type(uint64).max - 1) {
            return (false);
        }

        uint256 userNonce = userNonces[userCall.metaTx.from];

        // If the protocol indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // Protocols are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (protocolCall.callConfig.needsSequencedNonces()) {
            if (userCall.metaTx.nonce != userNonce + 1) {
                return (false);
            }

            unchecked {++userNonces[userCall.metaTx.from];}

            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            // NOTE: including the callConfig in the asyncNonceKey should prevent
            // issues occuring when a protocol may switch configs between blocking 
            // and async, since callConfig can double as another seed. 
            bytes32 asyncNonceKey = keccak256(abi.encode(userCall.metaTx.from, protocolCall.callConfig, userCall.metaTx.nonce + 1));
            
            if (asyncNonceFills[asyncNonceKey] != address(0)) {
                return (false);
            }

            asyncNonceFills[asyncNonceKey] = protocolCall.to;
        }

        return (true);
    }

    function _validateUser(ProtocolCall memory protocolCall, UserCall calldata userCall)
        internal
        view
        returns (bool)
    {
        
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up protocol userNonces
        if (!_verifyUserSignature(userCall)) {
            return (false);
        }

        if (userCall.metaTx.control != protocolCall.to) {
            return (false);
        }

        if (userCall.metaTx.nonce > type(uint64).max - 1) {
            return (false);
        }

        uint256 userNonce = userNonces[userCall.metaTx.from];

        // If the protocol indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // Protocols are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (protocolCall.callConfig.needsSequencedNonces()) {
            if (userCall.metaTx.nonce != userNonce + 1) {
                return (false);
            }

            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            // NOTE: including the callConfig in the asyncNonceKey should prevent
            // issues occuring when a protocol may switch configs between blocking 
            // and async, since callConfig can double as another seed. 
            bytes32 asyncNonceKey = keccak256(abi.encode(userCall.metaTx.from, protocolCall.callConfig, userCall.metaTx.nonce + 1));
            
            if (asyncNonceFills[asyncNonceKey] != address(0)) {
                return (false);
            }
        }
        return (true);
    }

    function _getProofHash(UserMetaTx memory metaTx) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                USER_TYPE_HASH,
                metaTx.from,
                metaTx.to,
                metaTx.deadline,
                metaTx.gas,
                metaTx.nonce,
                metaTx.maxFeePerGas,
                metaTx.value,
                metaTx.control,
                keccak256(metaTx.data)
            )
        );
    }

    function _verifyUserSignature(UserCall calldata userCall) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getProofHash(userCall.metaTx)).recover(userCall.signature);

        return signer == userCall.metaTx.from;
    }

    function getUserCallPayload(UserCall memory userCall) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userCall.metaTx));
    }

    function nextUserNonce(address user) external view returns (uint256 nextNonce) {
        nextNonce = userNonces[user] + 1;
    }
}
