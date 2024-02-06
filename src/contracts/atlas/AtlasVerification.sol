//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import { CallBits } from "../libraries/CallBits.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/GovernanceTypes.sol";

import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/ValidCallsTypes.sol";

import { EscrowBits } from "../libraries/EscrowBits.sol";
import { CallVerification } from "../libraries/CallVerification.sol";

import { DAppIntegration } from "./DAppIntegration.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

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
    using CallVerification for UserOperation;

    uint256 internal constant FULL_BITMAP = uint256(0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    uint256 internal constant FIRST_16_BITS_FULL = uint256(0xFFFF);
    uint256 internal constant FIRST_4_BITS_FULL = uint256(0xF);
    uint8 internal constant MAX_SOLVERS = type(uint8).max - 2;

    error InvalidCaller();

    constructor(address _atlas) EIP712("AtlasVerification", "0.0.1") DAppIntegration(_atlas) { }

    function validCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        uint256 msgValue,
        address msgSender,
        bool isSimulation
    )
        external
        returns (SolverOperation[] memory, ValidCallsResult)
    {
        // Verify that the calldata injection came from the dApp frontend
        // and that the signatures are valid.

        if (msg.sender != ATLAS) revert AtlasErrors.InvalidCaller();

        uint256 solverOpCount = solverOps.length;
        SolverOperation[] memory prunedSolverOps = new SolverOperation[](solverOpCount);

        {
            // bypassSignatoryApproval still verifies signature match, but does not check
            // if dApp approved the signor.
            (bool validAuctioneer, bool bypassSignatoryApproval) = _verifyAuctioneer(dConfig, userOp, solverOps, dAppOp);

            if (!validAuctioneer && !isSimulation) {
                return (prunedSolverOps, ValidCallsResult.InvalidAuctioneer);
            }

            // Check dapp signature
            if (!_verifyDApp(dConfig, dAppOp, msgSender, bypassSignatoryApproval, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.DAppSignatureInvalid);
            }

            // Check user signature
            if (!_verifyUser(dConfig, userOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.UserSignatureInvalid);
            }

            // Check solvers not over the max (253)
            if (solverOpCount > MAX_SOLVERS) {
                return (prunedSolverOps, ValidCallsResult.TooManySolverOps);
            }

            // Check if past user's deadline
            if (block.number > userOp.deadline) {
                if (userOp.deadline != 0 && !isSimulation) {
                    return (prunedSolverOps, ValidCallsResult.UserDeadlineReached);
                }
            }

            // Check if past dapp's deadline
            if (block.number > dAppOp.deadline) {
                if (dAppOp.deadline != 0 && !isSimulation) {
                    return (prunedSolverOps, ValidCallsResult.DAppDeadlineReached);
                }
            }

            // Check bundler matches dAppOp bundler
            if (dAppOp.bundler != address(0) && msgSender != dAppOp.bundler) {
                return (prunedSolverOps, ValidCallsResult.InvalidBundler);
            }

            // Check gas price is within user's limit
            if (tx.gasprice > userOp.maxFeePerGas) {
                return (prunedSolverOps, ValidCallsResult.GasPriceHigherThanMax);
            }

            // Check that the value of the tx is greater than or equal to the value specified
            if (msgValue < userOp.value) {
                return (prunedSolverOps, ValidCallsResult.TxValueLowerThanCallValue);
            }
        }

        // Otherwise, prune invalid solver ops
        uint256 validSolverCount;
        bytes32 userOpHash = userOp.getUserOperationHash();

        for (uint256 i = 0; i < solverOpCount; i++) {
            if (msgSender == solverOps[i].from || _verifySolverSignature(solverOps[i])) {
                // Validate solver signature

                SolverOperation memory solverOp = solverOps[i];

                if (tx.gasprice > solverOp.maxFeePerGas) continue;

                if (block.number > solverOp.deadline) continue;

                if (solverOp.from == userOp.from) continue;

                if (solverOp.to != ATLAS) continue;

                if (solverOp.solver == ATLAS || solverOp.solver == address(this)) continue;

                if (solverOp.userOpHash != userOpHash) continue;

                // If all initial checks succeed, add solver op to new array
                prunedSolverOps[validSolverCount] = solverOp;
                unchecked {
                    ++validSolverCount;
                }
            }
        }

        // Some checks are only needed when call is not a simulation
        if (isSimulation) {
            // Add all solver ops if simulation
            return (prunedSolverOps, ValidCallsResult.Valid);
        }

        // Verify a solver was successfully verified.
        if (validSolverCount == 0) {
            if (!dConfig.callConfig.allowsZeroSolvers()) {
                return (prunedSolverOps, ValidCallsResult.NoSolverOp);
            }

            if (dConfig.callConfig.needsFulfillment()) {
                return (prunedSolverOps, ValidCallsResult.NoSolverOp);
            }
        }

        return (prunedSolverOps, ValidCallsResult.Valid);
    }

    function _verifyAuctioneer(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        internal
        pure
        returns (bool valid, bool bypassSignatoryApproval)
    {
        bool validCallChainHash = !dConfig.callConfig.verifyCallChainHash()
            || dAppOp.callChainHash == CallVerification.getCallChainHash(dConfig, userOp, solverOps);

        if (!validCallChainHash) return (false, false);

        if (dConfig.callConfig.allowsUserAuctioneer() && dAppOp.from == userOp.sessionKey) return (true, true);

        if (dConfig.callConfig.allowsSolverAuctioneer() && dAppOp.from == solverOps[0].from) return (true, true);

        if (dConfig.callConfig.allowsUnknownAuctioneer()) return (true, true);

        return (true, false);
    }

    function getSolverPayload(SolverOperation calldata solverOp) external view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getSolverHash(solverOp));
    }

    function _verifySolverSignature(SolverOperation calldata solverOp) internal view returns (bool) {
        if (solverOp.signature.length == 0) return false;
        address signer = _hashTypedDataV4(_getSolverHash(solverOp)).recover(solverOp.signature);
        return signer == solverOp.from;
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
    function _verifyDApp(
        DAppConfig memory dConfig,
        DAppOperation calldata dAppOp,
        address msgSender,
        bool bypassSignatoryApproval,
        bool isSimulation
    )
        internal
        returns (bool)
    {
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp nonces

        bool bypassSignature = msgSender == dAppOp.from || (isSimulation && dAppOp.signature.length == 0);

        if (!bypassSignature && !_verifyDAppSignature(dAppOp)) {
            return false;
        }

        if (bypassSignatoryApproval) return true; // If bypass, return true after signature verification

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

        // Make sure the signer is currently enabled by dapp owner
        if (!signatories[keccak256(abi.encode(govData.governance, dAppOp.control, dAppOp.from))]) {
            bool bypassSignatoryCheck = isSimulation && dAppOp.from == address(0);
            if (!bypassSignatoryCheck) {
                return false;
            }
        }

        if (dAppOp.control != dConfig.to) {
            return false;
        }

        // If dAppOp.from is left blank and sim = true,
        // implies a simUserOp call, so dapp nonce check is skipped.
        if (dAppOp.from == address(0) && isSimulation) {
            return true;
        }

        // If the dapp indicated that they only accept sequenced nonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced nonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter.
        if (!_handleNonces(dAppOp.from, dAppOp.nonce, !dConfig.callConfig.needsSequencedDAppNonces(), isSimulation)) {
            return false;
        }

        return true;
    }

    // Returns true if nonce is valid, otherwise returns false
    function _handleNonces(address account, uint256 nonce, bool async, bool isSimulation) internal returns (bool) {
        if (nonce > type(uint128).max - 1) {
            return false;
        }

        // 0 Nonces are not allowed. Nonces start at 1 for both sequenced and async.
        if (nonce == 0) return false;

        NonceTracker memory nonceTracker = nonceTrackers[account];

        if (!async) {
            // SEQUENTIAL NONCES

            // Nonces must increase by 1 if sequential
            if (nonce != nonceTracker.lastUsedSeqNonce + 1) return false;

            // Return true here if simulation to avoid storing nonce updates
            if (isSimulation) return true;

            ++nonceTracker.lastUsedSeqNonce;
        } else {
            // ASYNC NONCES

            uint256 bitmapIndex = ((nonce - 1) / 240) + 1; // +1 because highestFullBitmap initializes at 0
            uint256 bitmapNonce = ((nonce - 1) % 240); // 1 -> 0, 240 -> 239. Needed for shifts in bitmap.

            bytes32 bitmapKey = keccak256(abi.encode(account, bitmapIndex));
            NonceBitmap memory nonceBitmap = nonceBitmaps[bitmapKey];
            uint256 bitmap = uint256(nonceBitmap.bitmap);

            // Check if nonce has already been used
            if (_nonceUsedInBitmap(bitmap, bitmapNonce)) {
                return false;
            }

            // Return true here if simulation to avoid storing nonce updates
            if (isSimulation) return true;

            // Mark nonce as used in bitmap
            bitmap |= 1 << bitmapNonce;
            nonceBitmap.bitmap = uint240(bitmap);

            // Update highestUsedNonce if necessary.
            // Add 1 back to bitmapNonce: 1 -> 1, 240 -> 240. As opposed to the shift form used above.
            if (bitmapNonce + 1 > uint256(nonceBitmap.highestUsedNonce)) {
                nonceBitmap.highestUsedNonce = uint8(bitmapNonce + 1);
            }

            // Mark bitmap as full if necessary
            if (bitmap == FULL_BITMAP) {
                // Update highestFullAsyncBitmap if necessary
                if (bitmapIndex == nonceTracker.highestFullAsyncBitmap + 1) {
                    nonceTracker = _incrementHighestFullAsyncBitmap(nonceTracker, account);
                }
            }

            nonceBitmaps[bitmapKey] = nonceBitmap;
        }

        nonceTrackers[account] = nonceTracker;
        return true;
    }

    function _incrementHighestFullAsyncBitmap(
        NonceTracker memory nonceTracker,
        address account
    )
        internal
        view
        returns (NonceTracker memory)
    {
        uint256 bitmap;
        do {
            unchecked {
                ++nonceTracker.highestFullAsyncBitmap;
            }
            uint256 bitmapIndex = uint256(nonceTracker.highestFullAsyncBitmap) + 1;
            bytes32 bitmapKey = keccak256(abi.encode(account, bitmapIndex));
            bitmap = uint256(nonceBitmaps[bitmapKey].bitmap);
        } while (bitmap == FULL_BITMAP);

        return nonceTracker;
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
        if (dAppOp.signature.length == 0) return false;
        address signer = _hashTypedDataV4(_getProofHash(dAppOp)).recover(dAppOp.signature);

        return signer == dAppOp.from;
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
    function _verifyUser(
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        address msgSender,
        bool isSimulation
    )
        internal
        returns (bool)
    {
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up dapp userNonces

        bool bypassSignature = msgSender == userOp.from || (isSimulation && userOp.signature.length == 0);

        if (!bypassSignature && !_verifyUserSignature(userOp)) {
            return false;
        }

        if (userOp.control != dConfig.to) {
            return false;
        }

        // If the dapp indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // DApps are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (!_handleNonces(userOp.from, userOp.nonce, !dConfig.callConfig.needsSequencedUserNonces(), isSimulation)) {
            return false;
        }

        return true;
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
        if (userOp.signature.length == 0) return false;
        address signer = _hashTypedDataV4(_getProofHash(userOp)).recover(userOp.signature);

        return signer == userOp.from;
    }

    function getUserOperationPayload(UserOperation memory userOp) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userOp));
    }

    // Returns the next nonce for the given account, in sequential or async mode
    function getNextNonce(address account, bool sequenced) external view returns (uint256) {
        NonceTracker memory nonceTracker = nonceTrackers[account];

        if (sequenced) {
            return nonceTracker.lastUsedSeqNonce + 1;
        } else {
            uint256 n;
            uint256 bitmap256;
            do {
                unchecked {
                    ++n;
                }
                // Async bitmaps start at index 1. I.e. accounts start with bitmap 0 = HighestFullAsyncBitmap
                bytes32 bitmapKey = keccak256(abi.encode(account, nonceTracker.highestFullAsyncBitmap + n));
                NonceBitmap memory nonceBitmap = nonceBitmaps[bitmapKey];
                bitmap256 = uint256(nonceBitmap.bitmap);
            } while (bitmap256 == FULL_BITMAP);

            uint256 remainder = _getFirstUnusedNonceInBitmap(bitmap256);
            return ((nonceTracker.highestFullAsyncBitmap + n - 1) * 240) + remainder;
        }
    }

    // Call if highestFullAsyncBitmap doesn't reflect real full bitmap of an account
    function manuallyUpdateNonceTracker(address account) external {
        if (msg.sender != account) revert AtlasErrors.OnlyAccount();

        NonceTracker memory nonceTracker = nonceTrackers[account];
        NonceBitmap memory nonceBitmap;

        // Checks the next 10 bitmaps for a higher full bitmap
        uint128 nonceIndexToCheck = nonceTracker.highestFullAsyncBitmap + 10;
        for (; nonceIndexToCheck > nonceTracker.highestFullAsyncBitmap; nonceIndexToCheck--) {
            bytes32 bitmapKey = keccak256(abi.encode(account, nonceIndexToCheck));
            nonceBitmap = nonceBitmaps[bitmapKey];

            if (nonceBitmap.bitmap == FULL_BITMAP) {
                nonceTracker.highestFullAsyncBitmap = nonceIndexToCheck;
                break;
            }
        }

        nonceTrackers[account] = nonceTracker;
    }

    // Only accurate for nonces 1 - 240 within a 256-bit bitmap
    function _nonceUsedInBitmap(uint256 bitmap, uint256 nonce) internal pure returns (bool) {
        return (bitmap & (1 << nonce)) != 0;
    }

    // Returns the first unused nonce in the given bitmap.
    // Returned nonce is 1-indexed. If 0 returned, bitmap is full.
    function _getFirstUnusedNonceInBitmap(uint256 bitmap) internal pure returns (uint256) {
        // Check the 240-bit bitmap, 16 bits at a time, if a 16 bit chunk is not full.
        // Then check the located 16-bit chunk, 4 bits at a time, for an unused 4-bit chunk.
        // Then loop normally from the start of the 4-bit chunk to find the first unused bit.

        for (uint256 i = 0; i < 240; i += 16) {
            // Isolate the next 16 bits to check
            uint256 chunk16 = (bitmap >> i) & FIRST_16_BITS_FULL;
            // Find non-full 16-bit chunk
            if (chunk16 != FIRST_16_BITS_FULL) {
                for (uint256 j = 0; j < 16; j += 4) {
                    // Isolate the next 4 bits within the 16-bit chunk to check
                    uint256 chunk4 = (chunk16 >> j) & FIRST_4_BITS_FULL;
                    // Find non-full 4-bit chunk
                    if (chunk4 != FIRST_4_BITS_FULL) {
                        for (uint256 k = 0; k < 4; k++) {
                            // Find first unused bit
                            if ((chunk4 >> k) & 0x1 == 0) {
                                // Returns 1-indexed nonce
                                return i + j + k + 1;
                            }
                        }
                    }
                }
            }
        }

        return 0;
    }
}
