//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/LockTypes.sol";

library SafetyBits {
    uint16 internal constant _EXECUTION_PHASE_OFFSET = uint16(type(BaseLock).max);
    uint16 internal constant _SAFETY_LEVEL_OFFSET = uint16(type(BaseLock).max) + uint16(type(ExecutionPhase).max);

    uint16 internal constant _LOCKED_X_SEARCHERS_X_REQUESTED = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Requested))
    );

    uint16 internal constant _LOCKED_X_SEARCHERS_X_VERIFIED = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Verified))
    );

    uint16 internal constant _ACTIVE_X_STAGING_X_UNSET = uint16(
        1 << uint16(BaseLock.Active) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _PENDING_X_RELEASING_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Releasing))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_STAGING_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Staging))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_USER_X_UNSET = uint16(
        1 << uint16(BaseLock.Active) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserCall))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_USER_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserCall))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _PENDING_X_SEARCHER_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_SEARCHER_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SearcherCalls))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _START_PAYMENTS = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCK_PAYMENTS = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_REFUND_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserRefund))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_VERIFICATION_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_VERIFICATION_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (_EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Verification))
            | 1 << (_SAFETY_LEVEL_OFFSET + uint16(SearcherSafety.Unset))
    );

    function turnVerificationLock(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _PENDING_X_RELEASING_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function confirmVerificationLock(EscrowKey memory self, address approvedCaller) internal pure returns (bool) {
        return (
            (self.lockState == _LOCKED_X_VERIFICATION_X_UNSET) && (self.approvedCaller == approvedCaller)
                && (self.callIndex == self.callMax - 1)
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

    function isValidVerificationLock(EscrowKey memory self, address caller) internal pure returns (bool) {
        // CASE: Previous searcher was successful
        if ((self.lockState == _LOCK_PAYMENTS)) {
            return (
                (caller != address(0)) && (self.approvedCaller == caller) && (self.callIndex > 2) // TODO: Could be == 2 if no searcher calls
                    && (self.callIndex < self.callMax)
            );

            // CASE: No searchers were successful
        } else {
            return (
                (self.lockState == _LOCKED_X_SEARCHERS_X_REQUESTED) && (caller != address(0))
                    && (self.approvedCaller == caller) && (self.callIndex == self.callMax - 1)
            );
        }
    }

    function turnRefundLock(EscrowKey memory self, address approvedCaller) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_VERIFICATION_X_UNSET;
        self.approvedCaller = approvedCaller;
        return self;
    }

    function isValidRefundLock(EscrowKey memory self, address caller) internal pure returns (bool) {
        return (
            (self.lockState == _ACTIVE_X_REFUND_X_UNSET) && (self.approvedCaller == caller)
                && (self.callIndex == self.callMax - 2)
        );
    }

    function turnPaymentsLockSearcher(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _ACTIVE_X_SEARCHER_X_UNSET;
        self.approvedCaller = approvedCaller;
        self.makingPayments = false;
        self.paymentsComplete = true;
        return self;
    }

    function turnPaymentsLockRefund(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _ACTIVE_X_REFUND_X_UNSET;
        self.approvedCaller = approvedCaller;
        self.callIndex = self.callMax - 2;
        self.makingPayments = false;
        self.paymentsComplete = true;
        return self;
    }

    function holdPaymentsLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCK_PAYMENTS;
        self.approvedCaller = address(0);
        return self;
    }

    function isValidPaymentsLock(EscrowKey memory self, address caller) internal pure returns (bool) {
        return (
            (self.lockState == _LOCK_PAYMENTS) && (caller != address(0)) && (self.approvedCaller == caller)
                && (self.makingPayments) && (!self.paymentsComplete)
        );
    }

    function turnSearcherLockNext(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _ACTIVE_X_SEARCHER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function turnSearcherLockRefund(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _ACTIVE_X_REFUND_X_UNSET;
        self.approvedCaller = approvedCaller;
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

    function confirmSearcherLock(EscrowKey memory self, address approvedCaller) internal pure returns (bool) {
        return ((self.lockState == _LOCKED_X_SEARCHERS_X_VERIFIED) && (self.approvedCaller == approvedCaller));
    }

    function isRevertedSearcherLock(EscrowKey memory self, address revertedSearcher) internal pure returns (bool) {
        return ((self.lockState == _LOCKED_X_SEARCHERS_X_REQUESTED) && (self.approvedCaller == revertedSearcher));
    }

    function holdSearcherLock(EscrowKey memory self, address nextSearcher) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SEARCHERS_X_REQUESTED;
        self.approvedCaller = nextSearcher;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function isValidSearcherLock(EscrowKey memory self, address caller) internal pure returns (bool) {
        // First searcher
        if (self.callIndex == 2) {
            return (
                (self.lockState == _LOCKED_X_USER_X_UNSET) && (caller != address(0))
                    && (self.approvedCaller != address(0)) && (self.approvedCaller != caller)
            );

            // All other searchers
        } else {
            // Means previous searcher was successful
            if (self.lockState == _LOCKED_X_SEARCHERS_X_VERIFIED) {
                return false;

                // Means previous searcher failed
            } else {
                return (
                    (self.lockState == _LOCKED_X_SEARCHERS_X_REQUESTED) && (caller != address(0))
                        && (self.approvedCaller != address(0)) && (self.approvedCaller != caller) && (self.callIndex > 2)
                        && (self.callIndex < self.callMax - 1)
                ) // < self.callMax - 1
                ;
            }
        }
    }

    function turnUserLock(EscrowKey memory self, address approvedCaller) internal pure returns (EscrowKey memory) {
        self.lockState = _PENDING_X_SEARCHER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
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

    function isValidUserLock(
        EscrowKey memory self,
        address // caller
    ) internal pure returns (bool) {
        return
        //(self.lockState == _ACTIVE_X_USER_X_UNSET) &&
        //(caller != address(0)) &&
        //(self.approvedCaller == caller) &&
        ((self.callIndex == 1));
    }

    function turnStagingLock(EscrowKey memory self, address approvedCaller) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_USER_X_UNSET;
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

    function isValidStagingLock(EscrowKey memory self, address caller) internal pure returns (bool) {
        return (
            (self.lockState == _ACTIVE_X_STAGING_X_UNSET) && (caller != address(0)) && (self.approvedCaller == caller)
                && (self.callIndex == 0)
        );
    }

    function canReleaseEscrowLock(EscrowKey memory self, address caller) internal pure returns (bool) {
        return ((self.approvedCaller == caller) && (self.callIndex == self.callMax)) //&&
            //(self.lockState == _LOCKED_X_VERIFICATION_X_UNSET)
        ;
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

    function isValidSearcherCallback(EscrowKey memory self, address caller) internal pure returns (bool) {
        return (self.lockState == _LOCKED_X_SEARCHERS_X_REQUESTED) && (self.approvedCaller == caller);
    }

    function turnSearcherLock(EscrowKey memory self, address msgSender) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SEARCHERS_X_VERIFIED;
        self.approvedCaller = msgSender;
        return self;
    }
}
