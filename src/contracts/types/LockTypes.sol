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
    uint32 dappGasLeft; // Gas used on preOps, allocateValue, and postOps hooks
}

// TODO double check we even need this struct after via-IR
struct StackVars {
    bytes32 userOpHash;
    address executionEnvironment;
    address bundler;
    bool isSimulation;
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
