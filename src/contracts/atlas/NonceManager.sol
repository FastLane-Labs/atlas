//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { AtlasConstants } from "src/contracts/types/AtlasConstants.sol";

contract NonceManager is AtlasConstants {
    // address => last used sequential nonce
    mapping(address => uint256) public userSequencialNonceTrackers;
    mapping(address => uint256) public dAppSequencialNonceTrackers;

    // address => word index => bitmap
    mapping(address => mapping(uint248 => uint256)) public userNonSequencialNonceTrackers;
    mapping(address => mapping(uint248 => uint256)) public dAppNonSequencialNonceTrackers;

    // NOTE: To prevent builder censorship, nonces can be processed in any order so long as they aren't duplicated and
    // as long as the dApp opts in to it.

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
            uint256 lastUsedNonce = userSequencialNonceTrackers[user];
            (validNonce, lastUsedNonce) = _handleSequentialNonces(lastUsedNonce, nonce);
            if (validNonce && !isSimulation) {
                // Update storage only if valid and not in simulation
                userSequencialNonceTrackers[user] = lastUsedNonce;
            }
        } else {
            (uint248 word, uint8 bitPos) = _bitmapPositions(nonce);
            uint256 bitmap = userNonSequencialNonceTrackers[user][word];
            (validNonce, bitmap) = _handleNonSequentialNonces(bitmap, bitPos);
            if (validNonce && !isSimulation) {
                // Update storage only if valid and not in simulation
                userNonSequencialNonceTrackers[user][word] = bitmap;
            }
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
        // 0 Nonces are not allowed. Nonces start at 1 for both sequential and non-sequential.
        if (nonce == 0) return false;

        if (sequential) {
            uint256 lastUsedNonce = dAppSequencialNonceTrackers[dAppSignatory];
            (validNonce, lastUsedNonce) = _handleSequentialNonces(lastUsedNonce, nonce);
            if (validNonce && !isSimulation) {
                // Update storage only if valid and not in simulation
                dAppSequencialNonceTrackers[dAppSignatory] = lastUsedNonce;
            }
        } else {
            (uint248 word, uint8 bitPos) = _bitmapPositions(nonce);
            uint256 bitmap = dAppNonSequencialNonceTrackers[dAppSignatory][word];
            (validNonce, bitmap) = _handleNonSequentialNonces(bitmap, bitPos);
            if (validNonce && !isSimulation) {
                // Update storage only if valid and not in simulation
                dAppNonSequencialNonceTrackers[dAppSignatory][word] = bitmap;
            }
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
        return (true, ++lastUsedNonce);
    }

    /// @notice The _handleNonSequentialNonces internal function handles the verification of non-sequential nonces.
    /// @param bitmap The bitmap to verify the nonce bit position against.
    /// @param bitPos The bit position of the nonce to verify.
    /// @return A boolean indicating if the nonce is valid.
    /// @return The updated bitmap.
    function _handleNonSequentialNonces(uint256 bitmap, uint8 bitPos) internal pure returns (bool, uint256) {
        uint256 bit = 1 << bitPos;
        uint256 flipped = bitmap ^= bit;

        // Nonce has already been used
        if (flipped & bit == 0) return (false, bitmap);

        return (true, bitmap);
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
            nextNonce = userSequencialNonceTrackers[user] + 1;
        } else {
            // Set the starting position to 1 to skip the 0 nonce
            nextNonce = _getNextNonSequentialNonce(user, 0, 1, true);
        }
    }

    /// @notice Returns the next valid nonce after `refNonce` for the given user, in non-sequential mode.
    /// @param user The address of the user for which to retrieve the next nonce.
    /// @param refNonce The nonce to start the search from.
    /// @return The next nonce for the given user.
    function getUserNextNonceAfter(address user, uint256 refNonce) external view returns (uint256) {
        (uint248 word, uint8 bitPos) = _nextNonceBitmapPositions(refNonce);
        return _getNextNonSequentialNonce(user, word, bitPos, true);
    }

    /// @notice Returns the next nonce for the given dApp signatory, in sequential or non-sequential mode.
    /// @param dApp The address of the dApp signatory for which to retrieve the next nonce.
    /// @param sequential A boolean indicating if the nonce should be sequential (true) or non-sequential (false).
    /// @return nextNonce The next nonce for the given dApp.
    function getDAppNextNonce(address dApp, bool sequential) external view returns (uint256 nextNonce) {
        if (sequential) {
            nextNonce = dAppSequencialNonceTrackers[dApp] + 1;
        } else {
            // Set the starting position to 1 to skip the 0 nonce
            nextNonce = _getNextNonSequentialNonce(dApp, 0, 1, false);
        }
    }

    /// @notice Returns the next valid nonce after `refNonce` for the given dApp signatory, in non-sequential mode.
    /// @param dApp The address of the dApp signatory for which to retrieve the next nonce.
    /// @param refNonce The nonce to start the search from.
    /// @return The next nonce for the given dApp.
    function getDAppNextNonceAfter(address dApp, uint256 refNonce) external view returns (uint256) {
        (uint248 word, uint8 bitPos) = _nextNonceBitmapPositions(refNonce);
        return _getNextNonSequentialNonce(dApp, word, bitPos, false);
    }

    /// @notice Returns the next nonce for the given account, in non-sequential mode.
    /// @param account The account to get the next nonce for.
    /// @param word The word index to start the search from.
    /// @param bitPos The bit position to start the search from.
    /// @param isUser A boolean indicating if the account is a user (true) or a dApp (false).
    /// @return nextNonce The next nonce for the given account.
    function _getNextNonSequentialNonce(
        address account,
        uint248 word,
        uint8 bitPos,
        bool isUser
    )
        internal
        view
        returns (uint256 nextNonce)
    {
        while (true) {
            uint256 bitmap =
                isUser ? userNonSequencialNonceTrackers[account][word] : dAppNonSequencialNonceTrackers[account][word];

            if (bitmap == type(uint256).max) {
                // Full bitmap, move to the next word
                ++word;
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
                    ++word;
                    bitPos = 0;
                    break;
                }

                bitmap >>= 1;
                ++bitPos;
            }

            if (nextWord) {
                continue;
            }

            nextNonce = _nonceFromWordAndPos(word, bitPos);
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
    /// @return word The word position or index into the bitmap of the next nonce.
    /// @return bitPos The bit position of the next nonce.
    function _nextNonceBitmapPositions(uint256 refNonce) internal pure returns (uint248 word, uint8 bitPos) {
        (word, bitPos) = _bitmapPositions(refNonce);
        if (bitPos == type(uint8).max) {
            // End of the bitmap, move to the next word
            ++word;
            bitPos = 0;
        } else {
            // Otherwise, just move to the next bit
            ++bitPos;
        }
    }

    /// @notice Returns the index of the bitmap and the bit position within the bitmap. Used for non-sequenced nonces.
    /// @param nonce The nonce to get the associated word and bit positions.
    /// @return word The word position or index into the bitmap.
    /// @return bitPos The bit position.
    /// @dev The first 248 bits of the nonce value is the index of the desired bitmap.
    /// @dev The last 8 bits of the nonce value is the position of the bit in the bitmap.
    function _bitmapPositions(uint256 nonce) internal pure returns (uint248 word, uint8 bitPos) {
        word = uint248(nonce >> 8);
        bitPos = uint8(nonce);
    }

    /// @notice Constructs a nonce from a word and a position inside the word.
    /// @param word The word position or index into the bitmap.
    /// @param bitPos The bit position.
    /// @return nonce The nonce constructed from the word and position.
    /// @dev The first 248 bits of the nonce value is the index of the desired bitmap.
    /// @dev The last 8 bits of the nonce value is the position of the bit in the bitmap.
    function _nonceFromWordAndPos(uint248 word, uint8 bitPos) internal pure returns (uint256 nonce) {
        nonce = uint256(word) << 8;
        nonce |= bitPos;
    }
}
