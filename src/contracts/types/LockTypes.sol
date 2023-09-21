//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct EscrowKey {
    address approvedCaller;
    bool makingPayments;
    bool paymentsComplete;
    uint8 callIndex;
    uint8 callMax;
    uint16 lockState; // bitwise
    uint32 gasRefund;
}

enum SolverSafety {
    Unset,
    Requested,
    Verified
}

enum BaseLock {
    Unlocked,
    Pending,
    Active,
    Locked
}

enum ExecutionPhase {
    Uninitialized,
    PreOps,
    UserOperation,
    SolverOperations,
    HandlingPayments,
    UserRefund,
    PostOps,
    Releasing
}
