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
- L260 `return uint256(SolverOutcome.SolverOpReverted);` - The default case in the switch statement is unreachable (as intended)

Last updated: 2024-Jan-25

### Factory.sol

Coverage as per coverage report:

- Lines: 14/16 (87.5%)
- Functions: 6/6 (100%)

Work Needed:

- Only L78 and L80 in `_setExecutionEnvironment`. L80 is assembly, coverage might get tricky.

Last updated: 2024-Jan-30

### AtlETH.sol

Fully tested in `/test/AtlETH.t.sol`.

Coverage as per coverage report:

- Lines: 93/93 (100%)
- Functions: 26/26 (100%)

Last updated: 2024-Mar-05

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

Coverage as per coverage report:

- Lines: 166/176 (94.3%)
- Functions: 19/19 (100%)

Unreachable Code:

- L368 Cannot be reached as `_verifyDApp` would return false before L278 if either dAppOp.control or dConfig.to are invalid, and if both are valid then this `return false` line would be bypassed.

Coverage Bugs:

- L139 `_verifyAuctioneer` is called as the lines of the internal function have full coverage.
- L450 `_handleNonces` last return line is covered as function is tested without revert.
- L471 `_incrementHighestFullAsyncBitmap` last return line is covered as function is tested without revert.
- L625 the `break` in `manuallyUpdateNonceTracker` is covered if the line above is covered, which it is.

Not Covered By Tests:

- The `if (userOp.from.code.length > 0)` block in _verifyUser for ERC-4337 Smart Wallets.

Last updated: 2024-Mar-06

### DAppIntegration.sol

Effective Test Coverage: 100%

Coverage as per coverage report:

- Lines: 34/35 (97.1%)
- Functions: 5/5 (100%)

Coverage Bugs:

- L114 `break` is covered because the lines above in the if block are covered

Last updated: 2024-Mar-07

### Mimic.sol

Effective Test Coverage: 100%

Coverage as per coverage report:

- Lines: 2/3 (66.7%)
- Functions: 1/1 (100%)

Coverage Bugs:

- L55 `return output` is shown as not covered, but it is covered in the successful function call in `testMimicDelegatecall`.

Last updated: 2024-Feb-07

### ExecutionEnvironment.sol

Coverage as per coverage report:

- Lines: 0/86 (0%)
- Functions: 0/14 (0%)

Work Needed:

- EE and ExecutionBase should be tested together. May be difficult because delegatecall involved.

Last updated: 2024-Jan-30

## Common Contracts - `/contracts/common`

### Permit69.sol

Effective Test Coverage: 100%

Coverage as per coverage report:

- Lines: 8/8 (100%)
- Functions: 3/4 (75%)

Notes:

- Coverage report shows internal virtual function `verifyCallerIsExecutionEnv` as not covered, but is covered in `Permit69.t.sol` in `testVerifyCallerIsExecutionEnv`.

Last updated: 2024-Feb-05

### ExecutionBase.sol

Coverage as per coverage report:

- Lines: 0/62 (0%)
- Functions: 0/25 (0%)

Work Needed:

- Full ExecutionBase coverage, done in conjunction with EE.

## DAppControl Base Contracts - `/contracts/dapp`

### DAppControl.sol

### ControlTemplate.sol

## Example DAppControls - `/contracts/examples`

### ChainlinkAtlasWrapper.sol (OEV Example)

Effective Test Coverage: 100%

Coverage as per coverage report:

- Lines: 31/31 (100%)
- Functions: 8/9 (88.9%)

Coverage Bugs:

- All lines are covered, but report says 1 function is not. Only functions with no internal lines are `fallback` and `receive`, which are tested in `testChainlinkAtlasWrapperCanReceiveETH`

Last updated: 2024-Mar-19

### ChainlinkDAppControl.sol (OEV Example)

Effective Test Coverage: 100%

Coverage as per coverage report:

- Lines: 48/52 (92.3%)
- Functions: 11/12 (91.7%)

Coverage Bugs:

- L86 `_allocateValueCall` hook is delegatecalled in the full Atlas test of the OEV module.
- L131 the `return newWrapper;` line in `createNewChainlinkAtlasWrapper` is tested in `test_ChainlinkDAppControl_createNewChainlinkAtlasWrapper`

Last updated: 2024-Mar-19


<!-- TODO add more folders and contracts -->