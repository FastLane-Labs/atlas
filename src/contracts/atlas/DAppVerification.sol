//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/UserCallTypes.sol";
import "../types/GovernanceTypes.sol";

import "../types/DAppApprovalTypes.sol";

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
    function _verifyDApp(DAppConfig calldata dConfig, DAppOperation calldata dAppOp)
        internal
        returns (bool)
    {
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp nonces
        if (!_verifyDAppSignature(dAppOp)) {
            return false;
        }

        // NOTE: to avoid replay attacks arising from key management errors,
        // the state changes below must be *saved* even if they render the
        // transaction invalid.
        // TODO: consider dapp-owned gas escrow.  Enshrined account
        // abstraction may render that redundant at a large scale, but
        // allocating different parts of the tx to different parties
        // will allow for optimized trustlessness. This could lead to
        // users not having to trust the front end at all - a huge
        // improvement over the current experience.

        GovernanceData memory govData = governance[dConfig.to];

        // Verify that the dapp is onboarded and that the call config is
        // genuine.
        bytes32 dAppKey = keccak256(abi.encode(dConfig.to, govData.governance, dConfig.callConfig));

        // Make sure the signer is currently enabled by dapp owner
        if (!signatories[keccak256(abi.encode(govData.governance, dAppOp.approval.from))]) {
            return (false);
        }

        if (dAppOp.approval.to != dConfig.to) {
            return (false);
        }

        // NOTE: This check does not work if DAppControl is a proxy contract.
        // To avoid exposure to social engineering vulnerabilities, disgruntled
        // former employees, or beneficiary uncertainty during intra-DAO conflict,
        // governance should refrain from using a proxy contract for DAppControl.
        if (dConfig.to.codehash == bytes32(0) || dapps[dAppKey] != dConfig.to.codehash) {
            return (false);
        }

        // Verify that DAppControl hasn't been updated.  
        // NOTE: Performing this check here allows the solvers' checks 
        // to be against the dAppOp proof's controlCodeHash to save gas.
        if (dConfig.to.codehash != dAppOp.approval.controlCodeHash) {
            return (false);
        }

        // If the dapp indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter.
        if (!_handleNonces(dAppOp.approval.from, dAppOp.approval.nonce, dConfig.callConfig.needsSequencedNonces())) {
            return (false);
        }

        return (true);
    }

    function _handleNonces(address account, uint256 nonce, bool async) internal returns (bool validNonce) {
        if (nonce > type(uint128).max - 1) {
            return (false);
        }
        
        if (nonce == 0) {
            return (false);
        }

        uint256 bitmapIndex = (nonce / 240) + 1; // +1 because highestFullBitmap initializes at 0
        uint256 bitmapNonce = (nonce % 240) + 1;

        bytes32 bitmapKey = keccak256(abi.encode(account, bitmapIndex));
        
        NonceBitmap memory nonceBitmap = asyncNonceBitmap[bitmapKey];

        uint256 bitmap = uint256(nonceBitmap.bitmap);
        if (bitmap & (1 << bitmapNonce) != 0) {
            return (false);
        }

        bitmap |= 1 << bitmapNonce;
        nonceBitmap.bitmap = uint240(bitmap);

        uint256 highestUsedBitmapNonce = uint256(nonceBitmap.highestUsedNonce);
        if (bitmapNonce > highestUsedBitmapNonce) {
            nonceBitmap.highestUsedNonce = uint8(bitmapNonce);
        }

        // Update the nonceBitmap
        asyncNonceBitmap[bitmapKey] = nonceBitmap;

        // Update the nonce tracker
        return _updateNonceTracker(account, highestUsedBitmapNonce, bitmapIndex, bitmapNonce, async);
    }

    function _updateNonceTracker(
        address account, uint256 highestUsedBitmapNonce, uint256 bitmapIndex, uint256 bitmapNonce, bool async
    ) 
        internal 
        returns (bool) 
    {
        NonceTracker memory nonceTracker = asyncNonceBitIndex[account];

        uint256 highestFullBitmap = uint256(nonceTracker.HighestFullBitmap);
        uint256 lowestEmptyBitmap = uint256(nonceTracker.LowestEmptyBitmap);

        // Handle non-async nonce logic
        if (!async) {
            if (bitmapIndex != highestFullBitmap + 1) {
                return (false);
            }

            if (bitmapNonce != highestUsedBitmapNonce +1) {
                return (false);
            }
        }

        if (bitmapNonce > uint256(239) || !async) {
            bool updateTracker;
        
            if (bitmapIndex > highestFullBitmap) {
                updateTracker = true;
                highestFullBitmap = bitmapIndex;
            }

            if (bitmapIndex + 2 > lowestEmptyBitmap) {
                updateTracker = true;
                lowestEmptyBitmap = (lowestEmptyBitmap > bitmapIndex ? lowestEmptyBitmap + 1 : bitmapIndex + 2);
            }

            if (updateTracker) {
                asyncNonceBitIndex[account] = NonceTracker({
                    HighestFullBitmap: uint128(highestFullBitmap),
                    LowestEmptyBitmap: uint128(lowestEmptyBitmap)
                });
            } 
        }
        return true;
    }

    function _getProofHash(DAppApproval memory approval) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                DAPP_TYPE_HASH,
                approval.from,
                approval.to,
                approval.value,
                approval.gas,
                approval.maxFeePerGas,
                approval.nonce,
                approval.deadline,
                approval.controlCodeHash,
                approval.userOpHash,
                approval.callChainHash
            )
        );
    }

    function _verifyDAppSignature(DAppOperation calldata dAppOp) internal view returns (bool) {
        if (dAppOp.signature.length == 0) { return false; }
        address signer = _hashTypedDataV4(_getProofHash(dAppOp.approval)).recover(dAppOp.signature);

        return signer == dAppOp.approval.from;
        // return true;
    }

    function getDAppOperationPayload(DAppOperation memory dAppOp) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(dAppOp.approval));
    }

    function getDAppApprovalPayload(DAppApproval memory dAppApproval) external view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(dAppApproval));
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
        if (!_verifyUserSignature(userOp)) {
            return false;
        }

        if (userOp.call.control != dConfig.to) {
            return (false);
        }

        // If the dapp indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (!_handleNonces(userOp.call.from, userOp.call.nonce, dConfig.callConfig.needsSequencedNonces())) {
            return (false);
        }

        return (true);
    }

    function _getProofHash(UserCall memory uCall) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                USER_TYPE_HASH,
                uCall.from,
                uCall.to,
                uCall.value,
                uCall.gas,
                uCall.maxFeePerGas,
                uCall.nonce,
                uCall.deadline,
                uCall.control,
                keccak256(uCall.data)
            )
        );
    }

    function _verifyUserSignature(UserOperation calldata userOp) internal view returns (bool) {
        if (userOp.signature.length == 0) { return false; }
        address signer = _hashTypedDataV4(_getProofHash(userOp.call)).recover(userOp.signature);

        return signer == userOp.call.from;
    }

    function getUserOperationPayload(UserOperation memory userOp) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userOp.call));
    }

    function getUserCallPayload(UserCall memory userCall) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userCall));
    }

    function getNextNonce(address account) external view returns (uint256 nextNonce) {
        NonceTracker memory nonceTracker = asyncNonceBitIndex[account];

        uint256 nextBitmapIndex = uint256(nonceTracker.HighestFullBitmap) + 1;
        uint256 lowestEmptyBitmap = uint256(nonceTracker.LowestEmptyBitmap);

        if (lowestEmptyBitmap == 0) {
            return 1; // uninitialized
        }

        bytes32 bitmapKey = keccak256(abi.encode(account, nextBitmapIndex));

        NonceBitmap memory nonceBitmap = asyncNonceBitmap[bitmapKey];

        uint256 highestUsedNonce = uint256(nonceBitmap.highestUsedNonce); //  has a +1 offset

        nextNonce = ((nextBitmapIndex - 1) * 240) + highestUsedNonce;
    }
}
