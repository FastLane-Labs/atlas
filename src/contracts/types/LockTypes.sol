//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

struct Lock {
    address activeEnvironment;
    ExecutionPhase phase;
    uint32 callConfig;
}

struct Context {
    address executionEnvironment; // not packed
    bytes32 userOpHash; // not packed
    address bundler;
    bool solverSuccessful;
    bool paymentsSuccessful;
    uint8 solverIndex;
    uint8 solverCount;
    ExecutionPhase phase;
    uint24 solverOutcome;
    bool bidFind;
    bool isSimulation;
    uint8 callDepth;
}

enum ExecutionPhase {
    Uninitialized,
    PreOps,
    UserOperation,
    PreSolver,
    SolverOperation,
    PostSolver,
    AllocateValue,
    PostOps
}
