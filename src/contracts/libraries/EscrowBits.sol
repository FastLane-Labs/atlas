//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/LockTypes.sol";
import "../types/EscrowTypes.sol";

library EscrowBits {
    uint64 internal constant _EXECUTION_PHASE_OFFSET = uint64(type(BaseLock).max);
    uint64 internal constant _SAFETY_LEVEL_OFFSET = uint64(type(BaseLock).max) + uint64(type(ExecutionPhase).max);

    uint256 public constant SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 public constant VALIDATION_GAS_LIMIT = 500_000;
    uint256 public constant GWEI = 1_000_000_000;
    uint256 public constant SEARCHER_GAS_BUFFER = 5; // out of 100
    uint256 public constant FASTLANE_GAS_BUFFER = 125_000; // integer amount

    uint256 internal constant _EXECUTION_REFUND = (
        1 << uint256(SearcherOutcome.CallReverted) | 1 << uint256(SearcherOutcome.BidNotPaid)
            | 1 << uint256(SearcherOutcome.CallValueTooHigh) | 1 << uint256(SearcherOutcome.UnknownError)
            | 1 << uint256(SearcherOutcome.CallbackFailed) | 1 << uint256(SearcherOutcome.EVMError)
            | 1 << uint256(SearcherOutcome.Success)
    );

    uint256 internal constant _NO_NONCE_UPDATE = (
        1 << uint256(SearcherOutcome.InvalidSignature) | 1 << uint256(SearcherOutcome.AlreadyExecuted)
            | 1 << uint256(SearcherOutcome.InvalidNonceUnder)
    );

    uint256 internal constant _BLOCK_VALID_EXECUTION = (
        1 << uint256(SearcherOutcome.InvalidNonceOver) | 1 << uint256(SearcherOutcome.PerBlockLimit)
            | 1 << uint256(SearcherOutcome.InvalidFormat) | 1 << uint256(SearcherOutcome.InvalidUserHash)
            | 1 << uint256(SearcherOutcome.InvalidBidsHash) | 1 << uint256(SearcherOutcome.GasPriceOverCap)
            | 1 << uint256(SearcherOutcome.UserOutOfGas) | 1 << uint256(SearcherOutcome.LostAuction)
    );

    uint256 internal constant _EXECUTED_WITH_ERROR = (
        1 << uint256(SearcherOutcome.BidNotPaid) | 1 << uint256(SearcherOutcome.CallReverted)
            | 1 << uint256(SearcherOutcome.BidNotPaid) | 1 << uint256(SearcherOutcome.CallValueTooHigh)
            | 1 << uint256(SearcherOutcome.CallbackFailed)
    );

    uint256 internal constant _EXECUTED_SUCCESSFULLY = (1 << uint256(SearcherOutcome.Success));

    uint256 internal constant _NO_USER_REFUND = (
        1 << uint256(SearcherOutcome.InvalidSignature) | 1 << uint256(SearcherOutcome.InvalidUserHash)
            | 1 << uint256(SearcherOutcome.InvalidBidsHash) | 1 << uint256(SearcherOutcome.GasPriceOverCap)
            | 1 << uint256(SearcherOutcome.InvalidSequencing)
    );

    uint256 internal constant _CALLDATA_REFUND = (
        1 << uint256(SearcherOutcome.InsufficientEscrow) | 1 << uint256(SearcherOutcome.InvalidNonceOver)
            | 1 << uint256(SearcherOutcome.UserOutOfGas) | 1 << uint256(SearcherOutcome.CallValueTooHigh)
    );

    uint256 internal constant _FULL_REFUND = (
        _EXECUTION_REFUND | 1 << uint256(SearcherOutcome.AlreadyExecuted)
            | 1 << uint256(SearcherOutcome.InvalidNonceUnder) | 1 << uint256(SearcherOutcome.PerBlockLimit)
            | 1 << uint256(SearcherOutcome.InvalidFormat)
    );

    uint256 internal constant _EXTERNAL_REFUND = (1 << uint256(SearcherOutcome.LostAuction));

    function canExecute(uint256 result) internal pure returns (bool) {
        return ((result >> 1) == 0);
    }

    function executionSuccessful(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_SUCCESSFULLY) != 0;
    }

    function executedWithError(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_WITH_ERROR) != 0;
    }

    function updateEscrow(uint256 result) internal pure returns (bool) {
        return !((result & _NO_NONCE_UPDATE != 0) || (result & _NO_USER_REFUND != 0));
    }

    function emitEvent(SearcherEscrow memory searcherEscrow) internal pure returns (bool) {
        return searcherEscrow.total != 0 || searcherEscrow.nonce != 0;
    }

    // NOTE: Order of bits for LockState:
    // Lowest bits = BaseLock
    // Middle bits = Execution Phase
    // Highest bits = SearcherSafety

    function isAtOrBelowLockDepth(BaseLock depth, uint64 lockState) internal pure returns (bool) {
        // BaseLock is the first few bits in the lockState
        return !((lockState & ~(uint64(1) << (uint64(depth) + 1))) != 0);
    }

    function isLockDepth(BaseLock depth, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << uint64(depth)) != 0;
    }

    function updateLockDepth(BaseLock newDepth, BaseLock oldDepth, uint64 lockState) internal pure returns (uint64) {
        lockState ^= uint64((1 << uint64(newDepth)) | (1 << uint64(oldDepth)));
        return lockState;
    }

    function isExecutionPhase(ExecutionPhase stage, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << (_EXECUTION_PHASE_OFFSET + uint64(stage))) != 0;
    }

    function updateExecutionPhase(ExecutionPhase newStage, ExecutionPhase oldStage, uint64 lockState)
        internal
        pure
        returns (uint64)
    {
        lockState ^= uint64(
            (1 << _EXECUTION_PHASE_OFFSET + uint64(newStage)) | (1 << _EXECUTION_PHASE_OFFSET + uint64(oldStage))
        );
        return lockState;
    }

    function isSafetyLevel(SearcherSafety safetyLevel, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << (_SAFETY_LEVEL_OFFSET + uint64(safetyLevel))) != 0;
    }

    function updateSafetyLevel(SearcherSafety newLevel, SearcherSafety oldLevel, uint64 lockState)
        internal
        pure
        returns (uint64)
    {
        lockState ^=
            uint64((1 << _SAFETY_LEVEL_OFFSET + uint64(newLevel)) | (1 << _SAFETY_LEVEL_OFFSET + uint64(oldLevel)));
        return lockState;
    }
}
