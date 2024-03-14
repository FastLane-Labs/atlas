//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

struct EscrowKey {
    address addressPointer;
    bool solverSuccessful;
    bool paymentsSuccessful;
    uint8 callIndex;
    uint8 callCount;
    uint16 lockState; // bitwise
    uint24 blank;
    bool bidFind;
    bool isSimulation;
    uint8 callDepth;
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
    PreSolver,
    SolverOperations,
    PostSolver,
    HandlingPayments,
    PostOps,
    Releasing
}
