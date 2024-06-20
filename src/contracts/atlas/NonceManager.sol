//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { AtlasConstants } from "src/contracts/types/AtlasConstants.sol";

contract NonceManager is AtlasConstants {
    struct NonceBitmap {
        uint8 highestUsedNonce;
        uint240 bitmap;
    }

    struct NonceTracker {
        uint128 lastUsedSeqNonce; // Sequential nonces tracked using only this value
        uint128 highestFullNonSeqBitmap; // Non-sequential nonces tracked using bitmaps
    }

    // from => nonceTracker
    mapping(address => NonceTracker) public userNonceTrackers;
    mapping(address => NonceTracker) public dAppNonceTrackers;

    // keccak256(from, isUser, bitmapNonceIndex) => nonceBitmap
    mapping(bytes32 => NonceBitmap) public nonceBitmaps;

    // NOTE: To prevent builder censorship, dApp nonces can be
    // processed in any order so long as they aren't duplicated and
    // as long as the dApp opts in to it

    /// @notice The _handleUserNonces internal function handles the verification of user nonces for both sequential and
    /// non-sequential nonce systems.
    /// @param user The address of the user to verify the nonce for.
    /// @param nonce The nonce to verify.
    /// @param sequential A boolean indicating if the nonce mode is sequential (true) or not (false)
    /// @param isSimulation A boolean indicating if the execution is a simulation.
    /// @return validNonce A boolean indicating if the nonce is valid.
    function _handleUserNonces(
        address user,
        uint256 nonce,
        bool sequential,
        bool isSimulation
    )
        internal
        returns (bool validNonce)
    {
        NonceTracker memory nonceTracker = userNonceTrackers[user];
        (validNonce, nonceTracker) = _handleNonces(nonceTracker, user, true, nonce, sequential);
        if (validNonce && !isSimulation) {
            // Update storage only if valid and not in simulation
            userNonceTrackers[user] = nonceTracker;
        }
    }

    /// @notice The _handleDAppNonces internal function handles the verification of dApp signatory nonces for both
    /// sequential and non-sequential nonce systems.
    /// @param dAppSignatory The address of the dApp to verify the nonce for.
    /// @param nonce The nonce to verify.
    /// @param sequential A boolean indicating if the nonce mode is sequential (true) or not (false)
    /// @param isSimulation A boolean indicating if the execution is a simulation.
    /// @return validNonce A boolean indicating if the nonce is valid.
    function _handleDAppNonces(
        address dAppSignatory,
        uint256 nonce,
        bool sequential,
        bool isSimulation
    )
        internal
        returns (bool validNonce)
    {
        NonceTracker memory nonceTracker = dAppNonceTrackers[dAppSignatory];
        (validNonce, nonceTracker) = _handleNonces(nonceTracker, dAppSignatory, false, nonce, sequential);
        if (validNonce && !isSimulation) {
            // Update storage only if valid and not in simulation
            dAppNonceTrackers[dAppSignatory] = nonceTracker;
        }
    }

    /// @notice The _handleNonces internal function handles the verification of nonces for both sequential and
    /// non-sequential nonce systems.
    /// @param nonceTracker The NonceTracker of the account to verify the nonce for.
    /// @param account The address of the account to verify the nonce for.
    /// @param isUser A boolean indicating if the account is a user (true) or a dApp (false).
    /// @param nonce The nonce to verify.
    /// @param sequential A boolean indicating if the nonce mode is sequential (true) or not (false)
    /// @return A boolean indicating if the nonce is valid.
    /// @return The updated NonceTracker.
    function _handleNonces(
        NonceTracker memory nonceTracker,
        address account,
        bool isUser,
        uint256 nonce,
        bool sequential
    )
        internal
        returns (bool, NonceTracker memory)
    {
        if (nonce > type(uint128).max - 1) {
            return (false, nonceTracker);
        }

        // 0 Nonces are not allowed. Nonces start at 1 for both sequential and non-sequential.
        if (nonce == 0) return (false, nonceTracker);

        if (sequential) {
            // SEQUENTIAL NONCES

            // Nonces must increase by 1 if sequential
            if (nonce != nonceTracker.lastUsedSeqNonce + 1) return (false, nonceTracker);

            ++nonceTracker.lastUsedSeqNonce;
        } else {
            // NON-SEQUENTIAL NONCES

            // Only 240 nonces per bitmap because uint240 used to track nonces,
            // while an additional uint8 used to track the highest used nonce in the bitmap.
            // Both the uint240 and uint8 are packed into a single storage slot.

            // `nonce` is passed as 1-indexed, but adjusted to 0-indexed for bitmap shift operations.
            // Then `bitmapIndex` is adjusted to be 1-indexed because `highestFullBitmap` initializes at 0, which
            // implies that the first non-full bitmap is at index 1.
            uint256 bitmapIndex = ((nonce - 1) / _NONCES_PER_BITMAP) + 1;
            uint256 bitmapNonce = ((nonce - 1) % _NONCES_PER_BITMAP);

            bytes32 bitmapKey = keccak256(abi.encode(account, isUser, bitmapIndex));
            NonceBitmap memory nonceBitmap = nonceBitmaps[bitmapKey];
            uint256 bitmap = uint256(nonceBitmap.bitmap);

            // Check if nonce has already been used
            if (_nonceUsedInBitmap(bitmap, bitmapNonce)) {
                return (false, nonceTracker);
            }

            // Mark nonce as used in bitmap
            bitmap |= 1 << bitmapNonce;
            nonceBitmap.bitmap = uint240(bitmap);

            // Update highestUsedNonce if necessary.
            // Add 1 back to bitmapNonce: 1 -> 1, 240 -> 240. As opposed to the shift form used above.
            if (bitmapNonce + 1 > uint256(nonceBitmap.highestUsedNonce)) {
                nonceBitmap.highestUsedNonce = uint8(bitmapNonce + 1);
            }

            // Mark bitmap as full if necessary
            if (bitmap == _FULL_BITMAP) {
                // Update highestFullNonSeqBitmap if necessary
                if (bitmapIndex == nonceTracker.highestFullNonSeqBitmap + 1) {
                    nonceTracker = _incrementHighestFullNonSeqBitmap(nonceTracker, account, isUser);
                }
            }

            nonceBitmaps[bitmapKey] = nonceBitmap;
        }

        return (true, nonceTracker);
    }

    /// @notice Increments the `highestFullNonSeqBitmap` of a given `nonceTracker` for the specified `account` until a
    /// non-fully utilized bitmap is found.
    /// @param nonceTracker The `NonceTracker` memory structure representing the current state of nonce tracking for a
    /// specific account.
    /// @param account The address of the account for which the nonce tracking is being updated. This is used to
    /// generate a unique key for accessing the correct bitmap from a mapping.
    /// @param isUser A boolean indicating if the account is a user (true) or a dApp (false).
    /// @return nonceTracker The updated `NonceTracker` structure with the `highestFullNonSeqBitmap` field modified to
    /// reflect the highest index of a bitmap that is not fully utilized.
    function _incrementHighestFullNonSeqBitmap(
        NonceTracker memory nonceTracker,
        address account,
        bool isUser
    )
        internal
        view
        returns (NonceTracker memory)
    {
        uint256 bitmap;
        do {
            unchecked {
                ++nonceTracker.highestFullNonSeqBitmap;
            }
            uint256 bitmapIndex = uint256(nonceTracker.highestFullNonSeqBitmap) + 1;
            bytes32 bitmapKey = keccak256(abi.encode(account, isUser, bitmapIndex));
            bitmap = uint256(nonceBitmaps[bitmapKey].bitmap);
        } while (bitmap == _FULL_BITMAP);

        return nonceTracker;
    }

    /// @notice Returns the next nonce for the given user, in sequential or non-sequential mode.
    /// @param user The address of the account for which to retrieve the next nonce.
    /// @param sequential A boolean indicating if the nonce should be sequential (true) or non-sequential (false).
    /// @return The next nonce for the given user.
    function getUserNextNonce(address user, bool sequential) external view returns (uint256) {
        NonceTracker memory nonceTracker = userNonceTrackers[user];
        return _getNextNonce(nonceTracker, user, true, sequential);
    }

    /// @notice Returns the next nonce for the given dApp signatory, in sequential or non-sequential mode.
    /// @param dApp The address of the dApp for which to retrieve the next nonce.
    /// @param sequential A boolean indicating if the nonce should be sequential (true) or non-sequential (false).
    /// @return The next nonce for the given user.
    function getDAppNextNonce(address dApp, bool sequential) external view returns (uint256) {
        NonceTracker memory nonceTracker = dAppNonceTrackers[dApp];
        return _getNextNonce(nonceTracker, dApp, false, sequential);
    }

    /// @notice Returns the next nonce for the given account, in sequential or non-sequential mode.
    /// @param nonceTracker The NonceTracker of the account for which to retrieve the next nonce.
    /// @param account The address of the account for which to retrieve the next nonce.
    /// @param isUser A boolean indicating if the account is a user (true) or a dApp (false).
    /// @param sequential A boolean indicating if the nonce should be sequential (true) or non-sequential (false).
    /// @return The next nonce for the given account.
    function _getNextNonce(
        NonceTracker memory nonceTracker,
        address account,
        bool isUser,
        bool sequential
    )
        internal
        view
        returns (uint256)
    {
        if (sequential) {
            return nonceTracker.lastUsedSeqNonce + 1;
        }

        uint256 n;
        uint256 bitmap;
        do {
            unchecked {
                ++n;
            }
            // Non-sequential bitmaps start at index 1. I.e. accounts start with bitmap 0 = HighestFullNonSeqBitmap
            bytes32 bitmapKey = keccak256(abi.encode(account, isUser, nonceTracker.highestFullNonSeqBitmap + n));
            NonceBitmap memory nonceBitmap = nonceBitmaps[bitmapKey];
            bitmap = uint256(nonceBitmap.bitmap);
        } while (bitmap == _FULL_BITMAP);

        uint256 remainder = _getFirstUnusedNonceInBitmap(bitmap);
        return ((nonceTracker.highestFullNonSeqBitmap + n - 1) * 240) + remainder;
    }

    /// @notice Manually updates the highestFullNonSeqBitmap of the caller to reflect the real full bitmap. This
    /// function is specific to user nonces.
    function manuallyUpdateUserNonSeqNonceTracker() external {
        NonceTracker memory nonceTracker = userNonceTrackers[msg.sender];
        userNonceTrackers[msg.sender] = _manuallyUpdateNonSeqNonceTracker(nonceTracker, msg.sender, true);
    }

    /// @notice Manually updates the highestFullNonSeqBitmap of the caller to reflect the real full bitmap. This
    /// function is specific to dApp nonces.
    function manuallyUpdateDAppNonSeqNonceTracker() external {
        NonceTracker memory nonceTracker = dAppNonceTrackers[msg.sender];
        dAppNonceTrackers[msg.sender] = _manuallyUpdateNonSeqNonceTracker(nonceTracker, msg.sender, false);
    }

    /// @notice Manually updates the highestFullNonSeqBitmap of an account to reflect the real full bitmap.
    /// @param nonceTracker The NonceTracker of the account for which the update should be made.
    /// @param account The address of the account for which the update should be made.
    /// @param isUser A boolean indicating if the account is a user (true) or a dApp (false).
    function _manuallyUpdateNonSeqNonceTracker(
        NonceTracker memory nonceTracker,
        address account,
        bool isUser
    )
        internal
        view
        returns (NonceTracker memory)
    {
        NonceBitmap memory nonceBitmap;

        // Checks the next 10 bitmaps for a higher full bitmap
        for (
            uint128 nonceIndexToCheck = nonceTracker.highestFullNonSeqBitmap + 10;
            nonceIndexToCheck > nonceTracker.highestFullNonSeqBitmap;
            nonceIndexToCheck--
        ) {
            bytes32 bitmapKey = keccak256(abi.encode(account, isUser, nonceIndexToCheck));
            nonceBitmap = nonceBitmaps[bitmapKey];

            if (nonceBitmap.bitmap == _FULL_BITMAP) {
                nonceTracker.highestFullNonSeqBitmap = nonceIndexToCheck;
                break;
            }
        }

        return nonceTracker;
    }

    /// @notice Checks if a nonce is used in a 256-bit bitmap.
    /// @dev Only accurate for the bitmap nonce range (0 - 239) within a 256-bit bitmap. This allows space in the slot
    /// for a uint8 representing the highest used nonce in the current bitmap.
    /// @param bitmap The 256-bit bitmap to check.
    /// @param bitmapNonce The nonce (in the range 0 - 239) to check.
    /// @return A boolean indicating if the nonce is used in the bitmap.
    function _nonceUsedInBitmap(uint256 bitmap, uint256 bitmapNonce) internal pure returns (bool) {
        return (bitmap & (1 << bitmapNonce)) != 0;
    }

    /// @notice Returns the first unused nonce in a 240-bit bitmap.
    /// @dev Finds the first unused nonce within a given 240-bit bitmap, checking 16 bits and then 4 bits at a time for
    /// efficiency.
    /// @param bitmap A uint256 where the first 240 bits are used to represent the used/unused status of nonces.
    /// @return The 1-indexed position of the first unused nonce within the bitmap, or 0 if all nonces represented by
    /// the bitmap are used.
    function _getFirstUnusedNonceInBitmap(uint256 bitmap) internal pure returns (uint256) {
        // Check the 240-bit bitmap, 16 bits at a time, if a 16 bit chunk is not full.
        // Then check the located 16-bit chunk, 4 bits at a time, for an unused 4-bit chunk.
        // Then loop normally from the start of the 4-bit chunk to find the first unused bit.

        for (uint256 i; i < 240; i += 16) {
            // Isolate the next 16 bits to check
            uint256 chunk16 = (bitmap >> i) & _FIRST_16_BITS_TRUE_MASK;
            // Find non-full 16-bit chunk
            if (chunk16 != _FIRST_16_BITS_TRUE_MASK) {
                for (uint256 j; j < 16; j += 4) {
                    // Isolate the next 4 bits within the 16-bit chunk to check
                    uint256 chunk4 = (chunk16 >> j) & _FIRST_4_BITS_TRUE_MASK;
                    // Find non-full 4-bit chunk
                    if (chunk4 != _FIRST_4_BITS_TRUE_MASK) {
                        for (uint256 k; k < 4; k++) {
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
