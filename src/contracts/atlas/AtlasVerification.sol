//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/GovernanceTypes.sol";

import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";

import {EscrowBits} from "../libraries/EscrowBits.sol";

import {DAppIntegration} from "./DAppIntegration.sol";

import "forge-std/Test.sol"; // TODO remove

// NOTE: AtlasVerification is the separate contract version of the DappVerification/DAppIntegration
// inheritance slice of the original Atlas design

// This contract exists so that dapp frontends can sign and confirm the
// calldata for users.  Users already trust the frontends to build and verify
// their calldata.  This allows users to know that any CallData sourced via
// an external relay (such as FastLane) has been verified by the already-trusted
// frontend
contract AtlasVerification is EIP712, DAppIntegration {
    using ECDSA for bytes32;
    using CallBits for uint32;

    constructor() EIP712("ProtoCallHandler", "0.0.1") {}

    // PORTED FROM ESCROW - TODO reorder

    function verifySolverOp(SolverOperation calldata solverOp, EscrowAccountData memory solverEscrow, uint256 gasWaterMark, bool auctionAlreadyComplete)
        external
        view
        returns (uint256 result, uint256 gasLimit, EscrowAccountData memory)
    {
        // verify solver's signature
        if (_verifySignature(solverOp)) {
            // verify the solver has correct usercalldata and the solver escrow checks
            (result, gasLimit, solverEscrow) = _verifySolverOperation(solverOp, solverEscrow);
        } else {
            (result, gasLimit) = (1 << uint256(SolverOutcome.InvalidSignature), 0);
            // solverEscrow returns null
        }

        result = _solverOpPreCheck(result, gasWaterMark, tx.gasprice, solverOp.maxFeePerGas, auctionAlreadyComplete);
        return (result, gasLimit, solverEscrow);
    }

    function _getSolverPayload(SolverOperation calldata solverOp) internal view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getSolverHash(solverOp));
    }

    function _verifySignature(SolverOperation calldata solverOp) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getSolverHash(solverOp)).recover(solverOp.signature);
        return signer == solverOp.from;
    }

    // TODO Revisit the EscrowAccountData memory solverEscrow arg. Needs to be passed through from Atlas, through callstack
    function _verifySolverOperation(SolverOperation calldata solverOp, EscrowAccountData memory solverEscrow)
        internal
        view
        returns (uint256 result, uint256 gasLimit, EscrowAccountData memory)
    {
        // TODO big unchecked block - audit/review carefully
        unchecked {
            if (solverOp.to != address(this)) {
                result |= 1 << uint256(SolverOutcome.InvalidTo);
            }

            if (solverOp.nonce <= uint256(solverEscrow.nonce)) {
                result |= 1 << uint256(SolverOutcome.InvalidNonceUnder);
            } else if (solverOp.nonce > uint256(solverEscrow.nonce) + 1) {
                result |= 1 << uint256(SolverOutcome.InvalidNonceOver);

                // TODO: reconsider the jump up for gapped nonces? Intent is to mitigate dmg
                // potential inflicted by a hostile solver/builder.
                solverEscrow.nonce = uint32(solverOp.nonce);
            } else {
                ++solverEscrow.nonce;
            }

            if (solverEscrow.lastAccessed >= uint64(block.number)) {
                result |= 1 << uint256(SolverOutcome.PerBlockLimit);
            } else {
                solverEscrow.lastAccessed = uint64(block.number);
            }

            gasLimit = (100) * (solverOp.gas < EscrowBits.SOLVER_GAS_LIMIT ? solverOp.gas : EscrowBits.SOLVER_GAS_LIMIT)
                / (100 + EscrowBits.SOLVER_GAS_BUFFER) + EscrowBits.FASTLANE_GAS_BUFFER;

            uint256 gasCost = (tx.gasprice * gasLimit) + (solverOp.data.length * CALLDATA_LENGTH_PREMIUM * tx.gasprice);

            // see if solver's escrow can afford tx gascost
            if (gasCost > solverEscrow.balance) {
                // charge solver for calldata so that we can avoid vampire attacks from solver onto user
                result |= 1 << uint256(SolverOutcome.InsufficientEscrow);
            }

            // Verify that we can lend the solver their tx value
            if (solverOp.value > address(this).balance - (gasLimit * tx.gasprice)) {
                result |= 1 << uint256(SolverOutcome.CallValueTooHigh);
            }

            // subtract out the gas buffer since the solver's metaTx won't use it
            gasLimit -= EscrowBits.FASTLANE_GAS_BUFFER;
        }

        return (result, gasLimit, solverEscrow);
    }

    function _getSolverHash(SolverOperation calldata solverOp) internal pure returns (bytes32 solverHash) {
        return keccak256(
            abi.encode(
                SOLVER_TYPE_HASH,
                solverOp.from,
                solverOp.to,
                solverOp.value,
                solverOp.gas,
                solverOp.maxFeePerGas,
                solverOp.nonce,
                solverOp.deadline,
                solverOp.solver,
                solverOp.control,
                solverOp.userOpHash,
                solverOp.bidToken,
                solverOp.bidAmount,
                keccak256(solverOp.data)
            )
        );
    }

    // BITWISE STUFF
    function _solverOpPreCheck(
        uint256 result,
        uint256 gasWaterMark,
        uint256 txGasPrice,
        uint256 maxFeePerGas,
        bool auctionAlreadyComplete
    ) internal pure returns (uint256) {
        if (auctionAlreadyComplete) {
            result |= 1 << uint256(SolverOutcome.LostAuction);
        }

        if (gasWaterMark < EscrowBits.VALIDATION_GAS_LIMIT + EscrowBits.SOLVER_GAS_LIMIT) {
            // Make sure to leave enough gas for dApp validation calls
            result |= 1 << uint256(SolverOutcome.UserOutOfGas);
        }

        if (txGasPrice > maxFeePerGas) {
            result |= 1 << uint256(SolverOutcome.GasPriceOverCap);
        }

        return result;
    }


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
    function verifyDApp(DAppConfig memory dConfig, DAppOperation calldata dAppOp)
        external
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
        if (!signatories[keccak256(abi.encode(govData.governance, dAppOp.from))]) {
            return (false);
        }

        if (dAppOp.control != dConfig.to) {
            return (false);
        }

        // NOTE: This check does not work if DAppControl is a proxy contract.
        // To avoid exposure to social engineering vulnerabilities, disgruntled
        // former employees, or beneficiary uncertainty during intra-DAO conflict,
        // governance should refrain from using a proxy contract for DAppControl.
        if (dConfig.to.codehash == bytes32(0) || dapps[dAppKey] != dConfig.to.codehash) {
            return (false);
        }

        // If the dapp indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter.
        if (!_handleNonces(dAppOp.from, dAppOp.nonce, dConfig.callConfig.needsSequencedNonces())) {
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

    function _getProofHash(DAppOperation memory approval) internal pure returns (bytes32 proofHash) {
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
                approval.control,
                approval.userOpHash,
                approval.callChainHash
            )
        );
    }

    function _verifyDAppSignature(DAppOperation calldata dAppOp) internal view returns (bool) {
        if (dAppOp.signature.length == 0) { return false; }
        address signer = _hashTypedDataV4(_getProofHash(dAppOp)).recover(dAppOp.signature);

        return signer == dAppOp.from;
        // return true;
    }

    function getDAppOperationPayload(DAppOperation memory dAppOp) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(dAppOp));
    }

    function getDomainSeparator() external view returns (bytes32 domainSeparator) {
        domainSeparator = _domainSeparatorV4();
    }

    //
    // USER VERIFICATION
    //

    // Verify the user's meta transaction
    function verifyUser(DAppConfig memory dConfig, UserOperation calldata userOp)
        external
        returns (bool)
    {
        
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp userNonces
        if (!_verifyUserSignature(userOp)) {
            return false;
        }

        if (userOp.control != dConfig.to) {
            return (false);
        }

        // If the dapp indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (!_handleNonces(userOp.from, userOp.nonce, dConfig.callConfig.needsSequencedNonces())) {
            return (false);
        }

        return (true);
    }

    function _getProofHash(UserOperation memory userOp) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                USER_TYPE_HASH,
                userOp.from,
                userOp.to,
                userOp.value,
                userOp.gas,
                userOp.maxFeePerGas,
                userOp.nonce,
                userOp.deadline,
                userOp.dapp,
                userOp.control,
                keccak256(userOp.data)
            )
        );
    }

    function _verifyUserSignature(UserOperation calldata userOp) internal view returns (bool) {
        if (userOp.signature.length == 0) { return false; }
        address signer = _hashTypedDataV4(_getProofHash(userOp)).recover(userOp.signature);

        return signer == userOp.from;
    }

    function getUserOperationPayload(UserOperation memory userOp) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userOp));
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
