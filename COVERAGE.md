# Test Coverage Notes

Some parts of the codebase are either difficult to reach in tests, or do not register as covered in the test coverage report. This doc is to track those gaps in the test coverage report and explain each one.

## Core Atlas Contracts - `/contracts/atlas`

### Atlas.sol

### Escrow.sol

Fully tested in `/test/Escrow.t.sol`, besides the following unreachable lines:

- L177 `if (solverOp.to != address(this))` - Metacall reverts early in AtlasVerification if this condition is true.
- L260 `return uint256(SolverOutcome.CallReverted);` - The default case in the switch statement is unreachable (as intended)

Last updated: 2024-Jan-25

### Factory.sol

### AtlETH.sol

### GasAccounting.sol

### SafetyLocks.sol

### Storage.sol

### AtlasVerification.sol

### DAppIntegration.sol

## Common Contracts - `/contracts/common`

### Permit69.sol

### ExecutionBase.sol

## DApp Contracts - `/contracts/dapp`

### DAppControl.sol

### ControlTemplate.sol

<!-- TODO add more folders and contracts -->