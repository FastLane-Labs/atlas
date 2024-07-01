//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { AtlasConstants } from "src/contracts/types/AtlasConstants.sol";

contract NonceManager is AtlasConstants {
    // address => last used sequential nonce
    mapping(address => uint256) public userSequentialNonceTrackers;
    mapping(address => uint256) public dAppSequentialNonceTrackers;

    // address => word index => bitmap
    mapping(address => mapping(uint248 => uint256)) public userNonSequentialNonceTrackers;

    // NOTE: Non-sequential nonces are only enabled for users. If dApps nonces are not set to be sequential, their
    // validation is not enforced.

    // ---------------------------------------------------- //
    //                                                      //
    //                     VALIDATION                       //
    //       Below functions ensure nonces validity         //
    //                                                      //
    // ---------------------------------------------------- //

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
        // 0 Nonces are not allowed. Nonces start at 1 for both sequential and non-sequential.
        if (nonce == 0) return false;

        if (sequential) {
            uint256 lastUsedNonce = userSequentialNonceTrackers[user];
            (validNonce, lastUsedNonce) = _handleSequentialNonces(lastUsedNonce, nonce);
            if (validNonce && !isSimulation) {
                // Update storage only if valid and not in simulation
                userSequentialNonceTrackers[user] = lastUsedNonce;
            }
        } else {
            (uint248 wordIndex, uint8 bitPos) = _bitmapPositions(nonce);
            uint256 bitmap = userNonSequentialNonceTrackers[user][wordIndex];
            (validNonce, bitmap) = _handleNonSequentialNonces(bitmap, bitPos);
            if (validNonce && !isSimulation) {
                // Update storage only if valid and not in simulation
                userNonSequentialNonceTrackers[user][wordIndex] = bitmap;
            }
        }
    }

    /// @notice The _handleDAppNonces internal function handles the verification of dApp signatory nonces for sequential
    /// nonce systems.
    /// @param dAppSignatory The address of the dApp to verify the nonce for.
    /// @param nonce The nonce to verify.
    /// @param isSimulation A boolean indicating if the execution is a simulation.
    /// @return validNonce A boolean indicating if the nonce is valid.
    /// @dev DApps nonces are only handled in sequential mode.
    function _handleDAppNonces(
        address dAppSignatory,
        uint256 nonce,
        bool isSimulation
    )
        internal
        returns (bool validNonce)
    {
        // 0 Nonces are not allowed. Nonces start at 1 for both sequential and non-sequential.
        if (nonce == 0) return false;

        uint256 lastUsedNonce = dAppSequentialNonceTrackers[dAppSignatory];
        (validNonce, lastUsedNonce) = _handleSequentialNonces(lastUsedNonce, nonce);
        if (validNonce && !isSimulation) {
            // Update storage only if valid and not in simulation
            dAppSequentialNonceTrackers[dAppSignatory] = lastUsedNonce;
        }
    }

    /// @notice The _handleSequentialNonces internal function handles the verification of sequential nonces.
    /// @param lastUsedNonce The last used nonce.
    /// @param nonce The nonce to verify.
    /// @return A boolean indicating if the nonce is valid.
    /// @return The updated last used nonce.
    function _handleSequentialNonces(uint256 lastUsedNonce, uint256 nonce) internal pure returns (bool, uint256) {
        // Nonces must increase by 1 if sequential
        if (nonce != lastUsedNonce + 1) return (false, lastUsedNonce);
        unchecked {
            return (true, ++lastUsedNonce);
        }
    }

    /// @notice The _handleNonSequentialNonces internal function handles the verification of non-sequential nonces.
    /// @param bitmap The bitmap to verify the nonce bit position against.
    /// @param bitPos The bit position of the nonce to verify.
    /// @return A boolean indicating if the nonce is valid.
    /// @return The updated bitmap.
    function _handleNonSequentialNonces(uint256 bitmap, uint8 bitPos) internal pure returns (bool, uint256) {
        uint256 bit = 1 << bitPos;
        uint256 flipped = bitmap ^ bit;

        // Nonce has already been used
        if (flipped & bit == 0) return (false, bitmap);

        return (true, flipped);
    }

    // ---------------------------------------------------- //
    //                                                      //
    //                    ACQUISITION                       //
    //        Below functions retrieve valid nonces         //
    //                                                      //
    // ---------------------------------------------------- //

    /// @notice Returns the next nonce for the given user, in sequential or non-sequential mode.
    /// @param user The address of the user for which to retrieve the next nonce.
    /// @param sequential A boolean indicating if the nonce should be sequential (true) or non-sequential (false).
    /// @return nextNonce The next nonce for the given user.
    function getUserNextNonce(address user, bool sequential) external view returns (uint256 nextNonce) {
        if (sequential) {
            nextNonce = userSequentialNonceTrackers[user] + 1;
        } else {
            // Set the starting position to 1 to skip the 0 nonce
            nextNonce = _getNextNonSequentialNonce(user, 0, 1);
        }
    }

    /// @notice Returns the next valid nonce after `refNonce` for the given user, in non-sequential mode.
    /// @param user The address of the user for which to retrieve the next nonce.
    /// @param refNonce The nonce to start the search from.
    /// @return The next nonce for the given user.
    function getUserNextNonSeqNonceAfter(address user, uint256 refNonce) external view returns (uint256) {
        (uint248 wordIndex, uint8 bitPos) = _nextNonceBitmapPositions(refNonce);
        return _getNextNonSequentialNonce(user, wordIndex, bitPos);
    }

    /// @notice Returns the next nonce for the given dApp signatory, in sequential mode.
    /// @param dApp The address of the dApp signatory for which to retrieve the next nonce.
    /// @return nextNonce The next nonce for the given dApp.
    /// @dev DApps nonces are only handled in sequential mode.
    function getDAppNextNonce(address dApp) external view returns (uint256 nextNonce) {
        nextNonce = dAppSequentialNonceTrackers[dApp] + 1;
    }

    /// @notice Returns the next nonce for the given account, in non-sequential mode.
    /// @param user The user to get the next nonce for.
    /// @param wordIndex The word index to start the search from.
    /// @param bitPos The bit position to start the search from.
    /// @return nextNonce The next nonce for the given account.
    /// @dev Non-sequential nonces are only enabled for users.
    function _getNextNonSequentialNonce(
        address user,
        uint248 wordIndex,
        uint8 bitPos
    )
        internal
        view
        returns (uint256 nextNonce)
    {
        while (true) {
            uint256 bitmap = userNonSequentialNonceTrackers[user][wordIndex];

            if (bitmap == type(uint256).max) {
                // Full bitmap, move to the next word
                ++wordIndex;
                bitPos = 0;
                continue;
            }

            if (bitPos != 0) {
                // If the position is not 0, shift the bitmap to ignore the bits before position
                bitmap >>= bitPos;
            }

            bool nextWord;

            // Find the first zero bit in the bitmap
            while (bitmap & 1 == 1) {
                if (bitPos == type(uint8).max) {
                    // End of the bitmap, move to the next word
                    nextWord = true;
                    ++wordIndex;
                    bitPos = 0;
                    break;
                }

                bitmap >>= 1;
                ++bitPos;
            }

            if (nextWord) {
                continue;
            }

            nextNonce = _nonceFromWordAndPos(wordIndex, bitPos);
            break;
        }
    }

    // ---------------------------------------------------- //
    //                                                      //
    //                       HELPERS                        //
    //                 Utility functions                    //
    //                                                      //
    // ---------------------------------------------------- //

    /// @notice Returns the index of the bitmap and the bit position within the bitmap for the next nonce.
    /// @param refNonce The nonce to get the next nonce positions from.
    /// @return wordIndex The word position or index into the bitmap of the next nonce.
    /// @return bitPos The bit position of the next nonce.
    function _nextNonceBitmapPositions(uint256 refNonce) internal pure returns (uint248 wordIndex, uint8 bitPos) {
        (wordIndex, bitPos) = _bitmapPositions(refNonce);
        if (bitPos == type(uint8).max) {
            // End of the bitmap, move to the next word
            ++wordIndex;
            bitPos = 0;
        } else {
            // Otherwise, just move to the next bit
            ++bitPos;
        }
    }

    /// @notice Returns the index of the bitmap and the bit position within the bitmap. Used for non-sequenced nonces.
    /// @param nonce The nonce to get the associated word and bit positions.
    /// @return wordIndex The word position or index into the bitmap.
    /// @return bitPos The bit position.
    /// @dev The first 248 bits of the nonce value is the index of the desired bitmap.
    /// @dev The last 8 bits of the nonce value is the position of the bit in the bitmap.
    function _bitmapPositions(uint256 nonce) internal pure returns (uint248 wordIndex, uint8 bitPos) {
        wordIndex = uint248(nonce >> 8);
        bitPos = uint8(nonce);
    }

    /// @notice Constructs a nonce from a word and a position inside the word.
    /// @param wordIndex The word position or index into the bitmap.
    /// @param bitPos The bit position.
    /// @return nonce The nonce constructed from the word and position.
    /// @dev The first 248 bits of the nonce value is the index of the desired bitmap.
    /// @dev The last 8 bits of the nonce value is the position of the bit in the bitmap.
    function _nonceFromWordAndPos(uint248 wordIndex, uint8 bitPos) internal pure returns (uint256 nonce) {
        nonce = uint256(wordIndex) << 8;
        nonce |= bitPos;
    }
}
