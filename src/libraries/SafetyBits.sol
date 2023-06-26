//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    EscrowKey,
    BaseLock,
    ExecutionPhase,
    SearcherSafety

} from "../libraries/DataTypes.sol";

library SafetyBits {

    uint64 constant internal _EXECUTION_PHASE_OFFSET = uint64(type(BaseLock).max);
    uint64 constant internal _SAFETY_LEVEL_OFFSET = uint64(type(BaseLock).max) + uint64(type(ExecutionPhase).max);

    uint64 constant internal _UNTRUSTED_X_SEARCHERS_X_REQUESTED = uint64(
        1 << uint64(BaseLock.Untrusted) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.SearcherCalls)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Requested))
    );

    uint64 constant internal _UNTRUSTED_X_SEARCHERS_X_VERIFIED = uint64(
        1 << uint64(BaseLock.Untrusted) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.SearcherCalls)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Verified))
    );

    uint64 constant internal _ACTIVE_X_STAGING_X_UNSET = uint64(
        1 << uint64(BaseLock.Active) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.Staging)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _PENDING_X_RELEASING_X_UNSET = uint64(
        1 << uint64(BaseLock.Pending) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.Releasing)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _UNTRUSTED_X_STAGING_X_UNSET = uint64(
        1 << uint64(BaseLock.Untrusted) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.Staging)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _ACTIVE_X_USER_X_UNSET = uint64(
        1 << uint64(BaseLock.Active) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.UserCall)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _UNTRUSTED_X_USER_X_UNSET = uint64(
        1 << uint64(BaseLock.Untrusted) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.UserCall)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _PENDING_X_SEARCHER_X_UNSET = uint64(
        1 << uint64(BaseLock.Pending) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.SearcherCalls)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _ACTIVE_X_SEARCHER_X_UNSET = uint64(
        1 << uint64(BaseLock.Pending) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.SearcherCalls)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _START_PAYMENTS = uint64(
        1 << uint64(BaseLock.Pending) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.HandlingPayments)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _LOCK_PAYMENTS = uint64(
        1 << uint64(BaseLock.Untrusted) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.HandlingPayments)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _ACTIVE_X_REFUND_X_UNSET = uint64(
        1 << uint64(BaseLock.Pending) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.UserRefund)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _ACTIVE_X_VERIFICATION_X_UNSET = uint64(
        1 << uint64(BaseLock.Pending) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.Verification)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    uint64 constant internal _UNTRUSTED_X_VERIFICATION_X_UNSET = uint64(
        1 << uint64(BaseLock.Untrusted) |
        1 << (_EXECUTION_PHASE_OFFSET + uint64(ExecutionPhase.Verification)) |
        1 << (_SAFETY_LEVEL_OFFSET + uint64(SearcherSafety.Unset))
    );

    function turnVerificationLock(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _PENDING_X_RELEASING_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked{ ++self.callIndex; }
        return self;
    }

    function confirmVerificationLock(
        EscrowKey memory self
    ) internal pure returns (bool) {
        return (
            (self.lockState == _UNTRUSTED_X_VERIFICATION_X_UNSET) && 
            (self.approvedCaller == address(0)) && 
            (self.callIndex == self.callMax-2)
        );
    }

    function holdVerificationLock(
        EscrowKey memory self
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _UNTRUSTED_X_VERIFICATION_X_UNSET;
        self.approvedCaller = address(0);
        return self;
    }

    function isValidVerificationLock(
        EscrowKey memory self, 
        address caller
    ) internal pure returns (bool) {
        return (
            (self.lockState == _ACTIVE_X_VERIFICATION_X_UNSET) && 
            (caller != address(0)) &&
            (self.approvedCaller == caller) && 
            (self.callIndex == self.callMax-2)
        );
    }

    function turnRefundLock(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_VERIFICATION_X_UNSET;
        self.approvedCaller = approvedCaller;
        return self;
    }

    function isValidRefundLock(
        EscrowKey memory self, 
        address caller
    ) internal pure returns (bool) {
        return (
            (self.lockState == _ACTIVE_X_REFUND_X_UNSET) && 
            (caller != address(0)) &&
            (self.approvedCaller == caller) && 
            (self.callIndex == self.callMax-2)
        );
    }

    function turnPaymentsLockSearcher(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_SEARCHER_X_UNSET;
        self.approvedCaller = approvedCaller;
        self.makingPayments = false;
        self.paymentsComplete = true;
        return self;
    }

    function turnPaymentsLockRefund(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_REFUND_X_UNSET;
        self.approvedCaller = approvedCaller;
        self.makingPayments = false;
        self.paymentsComplete = true;
        return self;
    }

    function holdPaymentsLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCK_PAYMENTS;
        self.approvedCaller = address(0);
        return self;
    }

    function isValidPaymentsLock(
        EscrowKey memory self, 
        address caller
    ) internal pure returns (bool) {
        return (
            (self.lockState == _START_PAYMENTS) && 
            (caller != address(0)) &&
            (self.approvedCaller == caller) && 
            (self.makingPayments) &&
            (!self.paymentsComplete)
        );
    }

    function turnSearcherLockNext(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_SEARCHER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked{ ++self.callIndex; }
        return self;
    }

    function turnSearcherLockRefund(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_REFUND_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked{ ++self.callIndex; }
        return self;
    }

    function turnSearcherLockPayments(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.makingPayments = true;
        self.lockState = _START_PAYMENTS;
        self.approvedCaller = approvedCaller;
        unchecked{ ++self.callIndex; }
        return self;
    }

    function confirmSearcherLock(
        EscrowKey memory self,
        address searcherTo
    ) internal pure returns (bool) {
        return (
            (self.lockState == _UNTRUSTED_X_SEARCHERS_X_VERIFIED) && 
            (self.approvedCaller == searcherTo)
        );
    }

    function holdSearcherLock(
        EscrowKey memory self, 
        address nextSearcher
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _UNTRUSTED_X_SEARCHERS_X_REQUESTED;
        self.approvedCaller = nextSearcher;
        return self;
    }

    function isValidSearcherLock(
        EscrowKey memory self, 
        address caller
    ) internal pure returns (bool) {
        // First searcher
        if (self.callIndex == 2) {
            return (
                (self.lockState == _PENDING_X_SEARCHER_X_UNSET) && 
                (caller != address(0)) &&
                (self.approvedCaller == caller) && 
                (self.callIndex == 2)
            );

        // All other searchers    
        } else {
            return (
                (self.lockState == _ACTIVE_X_SEARCHER_X_UNSET) && 
                (caller != address(0)) &&
                (self.approvedCaller == caller) && 
                (self.callIndex < self.callMax)
            );
        }
    }

    function turnUserLock(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _PENDING_X_SEARCHER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked{ ++self.callIndex; }
        return self;
    }

    function holdUserLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _UNTRUSTED_X_USER_X_UNSET;
        self.approvedCaller = address(0);
        return self;
    }

    function isValidUserLock(
        EscrowKey memory self, 
        address caller
    ) internal pure returns (bool) {
        return (
            (self.lockState == _ACTIVE_X_USER_X_UNSET) && 
            (caller != address(0)) &&
            (self.approvedCaller == caller) && 
            (self.callIndex == 1)
        );
    }

    function turnStagingLock(
        EscrowKey memory self, 
        address approvedCaller
    ) internal pure returns (EscrowKey memory) {
        self.lockState = _ACTIVE_X_USER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked{ ++self.callIndex; }
        return self;
    }

    function holdStagingLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _UNTRUSTED_X_STAGING_X_UNSET;
        self.approvedCaller = address(0);
        return self;
    }

    function isValidStagingLock(
        EscrowKey memory self, 
        address caller
    ) internal pure returns (bool) {
        return (
            (self.lockState == _ACTIVE_X_STAGING_X_UNSET) && 
            (caller != address(0)) &&
            (self.approvedCaller == caller) && 
            (self.callIndex == 0)
        );
    }

    function canReleaseEscrowLock(
        EscrowKey memory self,
        address caller
    ) internal pure returns (bool) {
        return (
            (self.approvedCaller == caller) &&
            (self.callMax == self.callIndex-1) &&
            (self.lockState == _PENDING_X_RELEASING_X_UNSET)
        );
    }

    function initializeEscrowLock(
        EscrowKey memory self,
        uint8 searcherCallCount,
        address nextCaller
    ) internal pure returns (EscrowKey memory) {
        self.approvedCaller = nextCaller;
        self.callMax = searcherCallCount+3;
        self.lockState = _ACTIVE_X_STAGING_X_UNSET;
        return self;
    }

    function isValidSearcherCallback(EscrowKey memory self, address caller) internal pure returns (bool) {
        return (self.lockState == _UNTRUSTED_X_SEARCHERS_X_REQUESTED) && 
            (self.approvedCaller == caller);
    }

    function turnSearcherLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _UNTRUSTED_X_SEARCHERS_X_VERIFIED;
        self.approvedCaller = address(0);
        return self;
    }
}