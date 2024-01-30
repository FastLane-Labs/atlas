# Test Coverage Notes

Some parts of the codebase are either difficult to reach in tests, or do not register as covered in the test coverage report. This doc is to track those gaps in the test coverage report and explain each one.

## Core Atlas Contracts - `/contracts/atlas`

### Atlas.sol

Coverage as per coverage report:

- Lines: 33/73 (45.2%)
- Functions: 4/6 (66.7%)

Work Needed:

- Lots of work needed.

Last updated: 2024-Jan-30

### Escrow.sol

Fully tested in `/test/Escrow.t.sol`, besides the following unreachable lines:

- L177 `if (solverOp.to != address(this))` - Metacall reverts early in AtlasVerification if this condition is true.
- L260 `return uint256(SolverOutcome.CallReverted);` - The default case in the switch statement is unreachable (as intended)

Last updated: 2024-Jan-25

### Factory.sol

Coverage as per coverage report:

- Lines: 14/16 (87.5%)
- Functions: 6/6 (100%)

Work Needed:

- Only L78 and L80 in `_setExecutionEnvironment`. L80 is assembly, coverage might get tricky.

Last updated: 2024-Jan-30

### AtlETH.sol

Coverage as per coverage report:

- Lines: 42/78 (53.8%)
- Functions: 12/23 (52.2%)

Work Needed:

- View function tests
- AtlETH's ERC20 functions (approve, transfer, transferFrom)
- Permit (Also for ERC20 functionality)
- Branches in `_deduct`
- All `redeem` and `_redeem` functionality

Last updated: 2024-Jan-30

### GasAccounting.sol

Coverage as per coverage report:

- Lines: 81/82 (98.8%)
- Functions: 12/12 (100%)

Work Needed:

- Just 1 line: L36 in `contribute` (which calls `_contribute`)

Last updated: 2024-Jan-30

### SafetyLocks.sol

Coverage as per coverage report:

- Lines: 18/20 (90%)
- Functions: 5/6 (83.3%)

Work Needed:

- L32 calling `_checkIfUnlocked` in `_initializeEscrowLock`
- L86 `isUnlocked` view function (in true and false states)

Last updated: 2024-Jan-30

### Storage.sol

Does not show up on coverage report. Check `Storage.t.sol`.

Last updated: 2024-Jan-30

### AtlasVerification.sol

### DAppIntegration.sol

## Common Contracts - `/contracts/common`

### Permit69.sol

### ExecutionBase.sol

## DApp Contracts - `/contracts/dapp`

### DAppControl.sol

### ControlTemplate.sol

<!-- TODO add more folders and contracts -->