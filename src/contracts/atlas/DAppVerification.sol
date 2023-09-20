//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/CallTypes.sol";
import "../types/GovernanceTypes.sol";

import {Verification, DAppProof} from "../types/VerificationTypes.sol";

import {DAppIntegration} from "./DAppIntegration.sol";

import "forge-std/Test.sol"; // TODO remove

// This contract exists so that dapp frontends can sign and confirm the
// calldata for users.  Users already trust the frontends to build and verify
// their calldata.  This allows users to know that any CallData sourced via
// an external relay (such as FastLane) has been verified by the already-trusted
// frontend
contract DAppVerification is EIP712, DAppIntegration {
    using ECDSA for bytes32;
    using CallBits for uint32;

    bytes32 public constant DAPP_TYPE_HASH = keccak256(
        "DAppProof(address from,address to,uint256 nonce,uint256 deadline,bytes32 userOpHash,bytes32 callChainHash,bytes32 controlCodeHash)"
    );

    bytes32 public constant USER_TYPE_HASH = keccak256(
        "UserCall(address from,address to,uint256 deadline,uint256 gas,uint256 nonce,uint256 maxFeePerGas,uint256 value,address control,bytes32 data)"
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
    // DAPP VERIFICATION
    //

    // Verify that the dapp's front end generated the preOps
    // information and that it matches the on-chain data.
    // Verify that the dapp's front end's data is based on
    // the data submitted by the user and by the solvers.
    // NOTE: the dapp's front end is the last party in
    // the supply chain to submit data.  If any other party
    // (user, solver, FastLane,  or a collusion between
    // all of them) attempts to alter it, this check will fail
    function _verifyDApp(address userOpTo, DAppConfig calldata dConfig, Verification calldata verification)
        internal
        returns (bool)
    {
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp nonces
        require(_verifyDAppSignature(verification), "ERR-PV01 InvalidSignature");

        // NOTE: to avoid replay attacks arising from key management errors,
        // the state changes below must be *saved* even if they render the
        // transaction invalid.
        // TODO: consider dapp-owned gas escrow.  Enshrined account
        // abstraction may render that redundant at a large scale, but
        // allocating different parts of the tx to different parties
        // will allow for optimized trustlessness. This could lead to
        // users not having to trust the front end at all - a huge
        // improvement over the current experience.

        ApproverSigningData memory signatory = signatories[verification.proof.from];

        if (verification.proof.to != dConfig.to) {
            return (false);
        }

        // Make sure the signer is currently enabled by dapp owner
        // NOTE: check must occur after storing signature to prevent replays
        if (!signatory.enabled) {
            return (false);
        }

        // Verify that the dapp is onboarded and that the call config is
        // genuine.
        bytes32 key = keccak256(abi.encode(dConfig.to, userOpTo, signatory.governance, dConfig.callConfig));

        // NOTE: This check does not work if DAppControl is a proxy contract.
        // To avoid exposure to social engineering vulnerabilities, disgruntled
        // former employees, or beneficiary uncertainty during intra-DAO conflict,
        // governance should refrain from using a proxy contract for DAppControl.
        if (dConfig.to.codehash == bytes32(0) || dapps[key] != dConfig.to.codehash) {
            return (false);
        }

        // Verify that DAppControl hasn't been updated.  
        // NOTE: Performing this check here allows the solvers' checks 
        // to be against the verification proof's controlCodeHash to save gas.
        if (dConfig.to.codehash != verification.proof.controlCodeHash) {
            return (false);
        }

        if (verification.proof.nonce > type(uint64).max - 1) {
            return (false);
        }

        // If the dapp indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (dConfig.callConfig.needsSequencedNonces()) {
            if (verification.proof.nonce != signatory.nonce + 1) {
                return (false);
            }

            unchecked {++signatories[verification.proof.from].nonce;}
            
            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            // NOTE: including the callConfig in the asyncNonceKey should prevent
            // issues occuring when a dapp may switch configs between blocking 
            // and async, since callConfig can double as another seed. 
            bytes32 asyncNonceKey = keccak256(abi.encode(verification.proof.from, dConfig.callConfig, verification.proof.nonce + 1));
            
            if (asyncNonceFills[asyncNonceKey] != address(0)) {
                return (false);
            }

            asyncNonceFills[asyncNonceKey] = dConfig.to;
        }

        return (true);
    }

    function _getProofHash(DAppProof memory proof) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                DAPP_TYPE_HASH,
                proof.from,
                proof.to,
                proof.nonce,
                proof.deadline,
                proof.userOpHash,
                proof.callChainHash,
                proof.controlCodeHash
            )
        );
    }

    function _verifyDAppSignature(Verification calldata verification) internal view returns (bool) {
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
    function _verifyUser(DAppConfig calldata dConfig, UserOperation calldata userOp)
        internal
        returns (bool)
    {
        
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp userNonces
        require(_verifyUserSignature(userOp), "ERR-UV01 InvalidSignature");

        if (userOp.call.control != dConfig.to) {
            return (false);
        }

        if (userOp.call.nonce > type(uint64).max - 1) {
            return (false);
        }

        uint256 userNonce = userNonces[userOp.call.from];

        // If the dapp indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (dConfig.callConfig.needsSequencedNonces()) {
            if (userOp.call.nonce != userNonce + 1) {
                return (false);
            }

            unchecked {++userNonces[userOp.call.from];}

            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            // NOTE: including the callConfig in the asyncNonceKey should prevent
            // issues occuring when a dapp may switch configs between blocking 
            // and async, since callConfig can double as another seed. 
            bytes32 asyncNonceKey = keccak256(abi.encode(userOp.call.from, dConfig.callConfig, userOp.call.nonce + 1));
            
            if (asyncNonceFills[asyncNonceKey] != address(0)) {
                return (false);
            }

            asyncNonceFills[asyncNonceKey] = dConfig.to;
        }

        return (true);
    }

    function _validateUser(DAppConfig memory dConfig, UserOperation calldata userOp)
        internal
        view
        returns (bool)
    {
        
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp userNonces
        if (!_verifyUserSignature(userOp)) {
            return (false);
        }

        if (userOp.call.control != dConfig.to) {
            return (false);
        }

        if (userOp.call.nonce > type(uint64).max - 1) {
            return (false);
        }

        uint256 userNonce = userNonces[userOp.call.from];

        // If the dapp indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (dConfig.callConfig.needsSequencedNonces()) {
            if (userOp.call.nonce != userNonce + 1) {
                return (false);
            }

            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            // NOTE: including the callConfig in the asyncNonceKey should prevent
            // issues occuring when a dapp may switch configs between blocking 
            // and async, since callConfig can double as another seed. 
            bytes32 asyncNonceKey = keccak256(abi.encode(userOp.call.from, dConfig.callConfig, userOp.call.nonce + 1));
            
            if (asyncNonceFills[asyncNonceKey] != address(0)) {
                return (false);
            }
        }
        return (true);
    }

    function _getProofHash(UserCall memory uCall) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                USER_TYPE_HASH,
                uCall.from,
                uCall.to,
                uCall.deadline,
                uCall.gas,
                uCall.nonce,
                uCall.maxFeePerGas,
                uCall.value,
                uCall.control,
                keccak256(uCall.data)
            )
        );
    }

    function _verifyUserSignature(UserOperation calldata userOp) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getProofHash(userOp.call)).recover(userOp.signature);

        return signer == userOp.call.from;
    }

    function getUserOperationPayload(UserOperation memory userOp) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userOp.call));
    }

    function nextUserNonce(address user) external view returns (uint256 nextNonce) {
        nextNonce = userNonces[user] + 1;
    }
}
