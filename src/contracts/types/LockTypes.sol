//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

struct Context {
    bytes32 userOpHash; // not packed
    address executionEnvironment; // not packed
    uint24 solverOutcome;
    uint8 solverIndex;
    uint8 solverCount;
    uint8 callDepth;
    uint8 phase;
    bool solverSuccessful;
    bool bidFind;
    bool isSimulation;
    address bundler;
    uint32 dappGasLeft; // Gas used on preOps and allocateValue hooks
}

enum ExecutionPhase {
    Uninitialized,
    PreOps,
    UserOperation,
    PreSolver,
    SolverOperation,
    PostSolver,
    AllocateValue,
    FullyLocked
}
