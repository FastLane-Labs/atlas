//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/LockTypes.sol";

uint16 constant EXECUTION_PHASE_OFFSET = uint16(type(BaseLock).max) + 1;
uint16 constant SAFETY_LEVEL_OFFSET = uint16(type(BaseLock).max) + uint16(type(ExecutionPhase).max) + 2;

library SafetyBits {

    uint16 internal constant _LOCKED_X_SEARCHERS_X_REQUESTED = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Requested))
    );

    uint16 internal constant _LOCKED_X_SEARCHERS_X_VERIFIED = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Verified))
    );

    uint16 internal constant _ACTIVE_X_STAGING_X_UNSET = uint16(
        1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _PENDING_X_RELEASING_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Releasing))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_STAGING_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_USER_X_UNSET = uint16(
        1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserCall))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_USER_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserCall))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _PENDING_X_SEARCHER_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_SEARCHER_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCK_PAYMENTS = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _NO_SEARCHER_SUCCESS = uint16(
        1 << uint16(BaseLock.Active) | 
        1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification)) | 
        1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_REFUND_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserRefund))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_VERIFICATION_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    function pack(EscrowKey memory self)
        internal
        pure
        returns (bytes32 packedKey)
    {
        packedKey = bytes32(
            abi.encodePacked(
                self.approvedCaller,
                self.makingPayments,
                self.paymentsComplete,
                self.callIndex,
                self.callMax,
                self.lockState,
                self.gasRefund,
                uint16(0)
            )
        );
    }

    function holdVerificationLock(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _LOCKED_X_VERIFICATION_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function setAllSearchersFailed(EscrowKey memory self)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _NO_SEARCHER_SUCCESS;
        self.approvedCaller = address(0);
        self.callIndex = self.callMax - 1;
        return self;
    }

    function allocationComplete(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.makingPayments = false;
        self.paymentsComplete = true;
        return self;
    }

    function turnSearcherLockPayments(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.makingPayments = true;
        self.lockState = _LOCK_PAYMENTS;
        self.approvedCaller = approvedCaller;
        return self;
    }

    function holdSearcherLock(EscrowKey memory self, address nextSearcher) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SEARCHERS_X_REQUESTED;
        self.approvedCaller = nextSearcher;
        return self;
    }

    function holdUserLock(EscrowKey memory self, address approvedCaller) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_USER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function holdStagingLock(EscrowKey memory self, address protocolControl) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_STAGING_X_UNSET;
        self.approvedCaller = protocolControl;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function initializeEscrowLock(EscrowKey memory self, bool needsStaging, uint8 searcherCallCount, address nextCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.approvedCaller = nextCaller;
        self.callMax = searcherCallCount + 3;
        self.callIndex = needsStaging ? 0 : 1;
        self.lockState = needsStaging ? _ACTIVE_X_STAGING_X_UNSET : _ACTIVE_X_USER_X_UNSET;
        return self;
    }

    function turnSearcherLock(EscrowKey memory self, address msgSender) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SEARCHERS_X_VERIFIED;
        self.approvedCaller = msgSender;
        return self;
    }
}
