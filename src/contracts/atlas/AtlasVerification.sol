//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

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

// import "forge-std/Test.sol"; // TODO remove

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

    error InvalidCaller();

    constructor(address _atlas) EIP712("ProtoCallHandler", "0.0.1") DAppIntegration(_atlas) { }

    function validCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        address executionEnvironment,
        uint256 msgValue,
        address msgSender,
        bool isSimulation
    )
        external
        returns (SolverOperation[] memory, ValidCallsResult)
    {
        // Verify that the calldata injection came from the dApp frontend
        // and that the signatures are valid.

        if (msg.sender != ATLAS) revert InvalidCaller();

        uint256 solverOpCount = solverOps.length;
        SolverOperation[] memory prunedSolverOps = new SolverOperation[](solverOpCount);

        // bundler checks
        if (msgSender == userOp.from) {
            // user is bundling their own operation - check allowed and valid dapp signature/callchainhash

            if (!dConfig.callConfig.allowsUserBundler()) {
                return (prunedSolverOps, ValidCallsResult.UnknownBundlerNotAllowed);
            }

            // user should not sign their own operation and transaction together
            if (userOp.signature.length > 0) {
                return (prunedSolverOps, ValidCallsResult.UserSignatureInvalid);
            }

            // check dapp signature
            if (!_verifyDApp(dConfig, dAppOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.DAppSignatureInvalid);
            }

            // check callchainhash
            if (dAppOp.callChainHash != CallVerification.getCallChainHash(dConfig, userOp, solverOps) && !isSimulation)
            {
                return (prunedSolverOps, ValidCallsResult.InvalidSequence);
            }
        } else if (msgSender == dAppOp.from) {
            // dapp is bundling - always allowed, check valid user/dapp signature and callchainhash

            // check dapp signature
            if (!_verifyDApp(dConfig, dAppOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.DAppSignatureInvalid);
            }

            // check user signature
            if (!_verifyUser(dConfig, userOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.UserSignatureInvalid);
            }

            // check callchainhash
            if (dAppOp.callChainHash != CallVerification.getCallChainHash(dConfig, userOp, solverOps) && !isSimulation)
            {
                return (prunedSolverOps, ValidCallsResult.InvalidSequence);
            }
        } else if (msgSender == solverOps[0].from && solverOps.length == 1) {
            // potentially the winning solver is bundling - check that its allowed and only need to verify user
            // signature

            // check if protocol allows it
            if (!dConfig.callConfig.allowsSolverBundler()) {
                return (prunedSolverOps, ValidCallsResult.DAppSignatureInvalid);
            }

            // verify user signature
            if (!_verifyUser(dConfig, userOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.UserSignatureInvalid);
            }

            // verify the callchainhash if required by protocol
            if (dConfig.callConfig.verifySolverBundlerCallChainHash()) {
                if (
                    dAppOp.callChainHash != CallVerification.getCallChainHash(dConfig, userOp, solverOps)
                        && !isSimulation
                ) {
                    return (prunedSolverOps, ValidCallsResult.InvalidSequence);
                }
            }
        } else if (dConfig.callConfig.allowsUnknownBundler()) {
            // check if protocol allows unknown bundlers, and verify all signatures if they do

            // check dapp signature
            if (!_verifyDApp(dConfig, dAppOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.DAppSignatureInvalid);
            }

            // check user signature
            if (!_verifyUser(dConfig, userOp, msgSender, isSimulation)) {
                return (prunedSolverOps, ValidCallsResult.UserSignatureInvalid);
            }

            // check callchainhash
            if (dAppOp.callChainHash != CallVerification.getCallChainHash(dConfig, userOp, solverOps) && !isSimulation)
            {
                return (prunedSolverOps, ValidCallsResult.InvalidSequence);
            }
        } else {
            return (prunedSolverOps, ValidCallsResult.UnknownBundlerNotAllowed);
        }

        if (solverOps.length > type(uint8).max - 2) {
            return (prunedSolverOps, ValidCallsResult.TooManySolverOps);
        }

        if (block.number > userOp.deadline) {
            bool bypass = isSimulation && userOp.deadline == 0;
            if (!bypass) {
                return (prunedSolverOps, ValidCallsResult.UserDeadlineReached);
            }
        }

        if (block.number > dAppOp.deadline) {
            bool bypass = isSimulation && dAppOp.deadline == 0;
            if (!bypass) {
                return (prunedSolverOps, ValidCallsResult.DAppDeadlineReached);
            }
        }

        // Some checks are only needed when call is not a simulation
        if (isSimulation) {
            // Add all solver ops if simulation
            return (solverOps, ValidCallsResult.Valid);
        }

        if (tx.gasprice > userOp.maxFeePerGas) {
            return (prunedSolverOps, ValidCallsResult.GasPriceHigherThanMax);
        }

        // Check that the value of the tx is greater than or equal to the value specified
        if (msgValue < userOp.value) {
            return (prunedSolverOps, ValidCallsResult.TxValueLowerThanCallValue);
        }

        if (executionEnvironment.codehash == bytes32(0)) {
            return (prunedSolverOps, ValidCallsResult.ExecutionEnvEmpty);
        }

        // Otherwise, prune invalid solver ops
        uint256 validSolverCount;
        bytes32 userOpHash = userOp.getUserOperationHash();

        for (uint256 i = 0; i < solverOpCount; i++) {
            if (msgSender == solverOps[i].from || _verifySignature(solverOps[i])) {
                // Validate solver signature

                SolverOperation memory solverOp = solverOps[i];

                if (tx.gasprice > solverOp.maxFeePerGas) {
                    // Verify solver max gas price
                    continue;
                }

                if (block.number > solverOp.deadline) {
                    // Verify solver deadline
                    continue;
                }

                if (solverOp.from == userOp.from) {
                    continue;
                }

                if (solverOp.to != ATLAS) {
                    continue;
                }

                if (solverOp.solver == ATLAS || solverOp.solver == address(this)) {
                    continue;
                }

                if (solverOp.userOpHash != userOpHash) {
                    continue;
                }

                // If all initial checks succeed, add solver op to new array
                prunedSolverOps[i] = solverOp;
                unchecked {
                    ++validSolverCount;
                }
            }
        }

        if (!dConfig.callConfig.allowsZeroSolvers() && validSolverCount == 0) {
            return (prunedSolverOps, ValidCallsResult.NoSolverOp);
        }

        if (dConfig.callConfig.needsFulfillment() && validSolverCount == 0) {
            return (prunedSolverOps, ValidCallsResult.NoSolverOp);
        }

        return (prunedSolverOps, ValidCallsResult.Valid);
    }

    // PORTED FROM ESCROW - TODO reorder

    function getSolverPayload(SolverOperation calldata solverOp) external view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getSolverHash(solverOp));
    }

    function _verifySignature(SolverOperation calldata solverOp) internal view returns (bool) {
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
            bool bypassSignatoryCheck = isSimulation && dAppOp.from == address(0);
            if (!bypassSignatoryCheck) {
                return (false);
            }
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
        if (!_handleNonces(dAppOp.from, dAppOp.nonce, dConfig.callConfig.needsSequencedNonces(), isSimulation)) {
            return (false);
        }

        return (true);
    }

    function _handleNonces(
        address account,
        uint256 nonce,
        bool async,
        bool isSimulation
    )
        internal
        returns (bool validNonce)
    {
        if (nonce > type(uint128).max - 1) {
            return false;
        }

        if (!isSimulation) {
            if (nonce == 0) {
                // Allow 0 nonce for simulations to avoid unnecessary init txs
                return false;
            } else if (nonce == 1) {
                // Check if nonce needs to be initialized - do so if necessary. 
                _initializeNonce(account);
            }
        }

        uint256 bitmapIndex = (nonce / 240) + 1; // +1 because highestFullBitmap initializes at 0
        uint256 bitmapNonce = (nonce % 240) + 1;

        bytes32 bitmapKey = keccak256(abi.encode(account, bitmapIndex));

        NonceBitmap memory nonceBitmap = asyncNonceBitmap[bitmapKey];

        uint256 bitmap = uint256(nonceBitmap.bitmap);
        if (bitmap & (1 << bitmapNonce) != 0) {
            return false;
        }

        if (isSimulation) {
            // return early if simulation to avoid storing nonce updates
            return true;
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
        address account,
        uint256 highestUsedBitmapNonce,
        uint256 bitmapIndex,
        uint256 bitmapNonce,
        bool async
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
                return false;
            }

            if (bitmapNonce != highestUsedBitmapNonce + 1) {
                return false;
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
        if (dAppOp.signature.length == 0) return false;
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
        if (!_handleNonces(userOp.from, userOp.nonce, dConfig.callConfig.needsSequencedNonces(), isSimulation)) {
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
