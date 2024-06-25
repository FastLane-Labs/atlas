//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

struct Lock {
    address activeEnvironment;
    uint32 callConfig;
    uint8 phase;
}

struct Context {
    bytes32 userOpHash; // not packed
    address executionEnvironment; // not packed
    uint24 solverOutcome;
    uint8 callIndex;
    uint8 callCount;
    uint8 callDepth;
    uint8 phase;
    bool solverSuccessful;
    bool paymentsSuccessful;
    bool bidFind;
    bool isSimulation;
    address bundler;
}

enum ExecutionPhase {
    Uninitialized,
    PreOps,
    UserOperation,
    PreSolver,
    SolverOperations,
    PostSolver,
    AllocateValue,
    PostOps
}
