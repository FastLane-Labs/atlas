//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { FastLaneDataTypes } from "../libraries/DataTypes.sol";

import {
    SearcherEscrow,
    UserCall,
    CallConfig,
    BaseLock,
    ExecutionPhase,
    SearcherSafety
} from "../libraries/DataTypes.sol";

contract BitStuff is FastLaneDataTypes {

    uint64 constant internal _EXECUTION_PHASE_OFFSET = uint64(type(BaseLock).max);
    uint64 constant internal _SAFETY_LEVEL_OFFSET = uint64(type(BaseLock).max) + uint64(type(ExecutionPhase).max);

    function _canExecute(uint256 result) internal pure returns (bool) {
        return ((result >>1) == 0);
    }

    function _executionSuccessful(uint256 result) internal pure returns (bool) {
        return ((result >>2) == 0);
    }

    function _executedWithError(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_WITH_ERROR != 0);
    }

    function _updateEscrow(uint256 result) internal pure returns (bool) {
        return !((result & _NO_NONCE_UPDATE != 0) || (result & _NO_USER_REFUND != 0));
    }

    function _emitEvent(SearcherEscrow memory searcherEscrow) internal pure returns (bool) {
        return searcherEscrow.total != 0 || searcherEscrow.nonce != 0;
    }

    function _needsStaging(uint16 callConfig) internal pure returns (bool needsStaging) {
        needsStaging = (callConfig & 1 << uint16(CallConfig.CallStaging) != 0);
    }

    function _delegateStaging(uint16 callConfig) internal pure returns (bool delegateStaging) {
        delegateStaging = (callConfig & 1 << uint16(CallConfig.DelegateStaging) != 0);
    }

    function _fwdValueStaging(uint16 callConfig) internal pure returns (bool fwdValueStaging) {
        fwdValueStaging = (callConfig & 1 << uint16(CallConfig.FwdValueStaging) != 0);
    }

    function _delegateUser(uint16 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = (callConfig & 1 << uint16(CallConfig.DelegateUser) != 0);
    }

    function _delegateVerification(uint16 callConfig) internal pure returns (bool delegateVerification) {
        delegateVerification = (callConfig & 1 << uint16(CallConfig.DelegateStaging) != 0);
    }

    function _needsVerification(uint16 callConfig) internal pure returns (bool needsVerification) {
        needsVerification = (callConfig & 1 << uint16(CallConfig.CallStaging) != 0);
    }

    function _fwdValueVerification(uint16 callConfig) internal pure returns (bool fwdValueVerification) {
        fwdValueVerification = (callConfig & 1 << uint16(CallConfig.FwdValueStaging) != 0);
    }

    // NOTE: Order of bits for LockState:
    // Lowest bits = BaseLock
    // Middle bits = Execution Phase
    // Highest bits = SearcherSafety

    function _isAtOrBelowLockDepth(BaseLock depth, uint64 lockState) internal pure returns (bool) {
        // BaseLock is the first few bits in the lockState
        return !((lockState & ~(uint64(1) << (uint64(depth)+1))) != 0);
    }

    function _isLockDepth(BaseLock depth, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << uint64(depth)) != 0;
    }

    function _updateLockDepth(
        BaseLock newDepth, 
        BaseLock oldDepth,
        uint64 lockState
    ) internal pure returns (uint64) {
        lockState ^= uint64(
            (1 << uint64(newDepth)) | 
            (1 << uint64(oldDepth))
        );
        return lockState;
    }

    function _isExecutionPhase(ExecutionPhase stage, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << (_EXECUTION_PHASE_OFFSET + uint64(stage))) != 0;
    }

    function _updateExecutionPhase(
        ExecutionPhase newStage, 
        ExecutionPhase oldStage,
        uint64 lockState
    ) internal pure returns (uint64) {
        lockState ^= uint64(
            (1 << _EXECUTION_PHASE_OFFSET + uint64(newStage)) | 
            (1 << _EXECUTION_PHASE_OFFSET + uint64(oldStage))
        );
        return lockState;
    }

    function _isSafetyLevel(SearcherSafety safetyLevel, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << (_SAFETY_LEVEL_OFFSET + uint64(safetyLevel))) != 0;
    }

    function _updateSafetyLevel(
        SearcherSafety newLevel, 
        SearcherSafety oldLevel,
        uint64 lockState
    ) internal pure returns (uint64) {
        lockState ^= uint64(
            (1 << _SAFETY_LEVEL_OFFSET + uint64(newLevel)) | 
            (1 << _SAFETY_LEVEL_OFFSET + uint64(oldLevel))
        );
        return lockState;
    }
}