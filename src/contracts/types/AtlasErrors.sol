//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/ValidCallsTypes.sol";

contract AtlasErrors {
    // Simulator
    error Unauthorized();
    error Unreachable();
    error NoAuctionWinner();
    error InvalidEntryFunction();
    error SimulationPassed();

    error UserSimulationFailed();
    error UserSimulationSucceeded();
    error UserUnexpectedSuccess();
    error UserNotFulfilled();

    error BidFindSuccessful(uint256 bidAmount);
    error UnexpectedNonRevert();

    error SolverBidUnpaid();
    error BalanceNotReconciled();
    error SolverOperationReverted();
    error AlteredControl();
    error InvalidEntry();
    error CallbackNotCalled();
    error IntentUnfulfilled();
    error PreSolverFailed();
    error PostSolverFailed();

    error VerificationSimFail(uint256 validCallsResult);
    error PreOpsSimFail();
    error UserOpSimFail();
    error SolverSimFail(uint256 solverOutcomeResult); // uint param is result returned in `verifySolverOp`
    error PostOpsSimFail();
    error ValidCalls(ValidCallsResult);

    // Execution Environment
    error InvalidUser();
    error InvalidTo();
    error InvalidCodeHash();
    error PreOpsDelegatecallFail();
    error UserOpValueExceedsBalance();
    error UserWrapperDelegatecallFail();
    error UserWrapperCallFail();
    error PostOpsDelegatecallFail();
    error PostOpsDelegatecallReturnedFalse();
    error SolverMetaTryCatchIncorrectValue();
    error AllocateValueDelegatecallFail();
    error NotEnvironmentOwner();
    error ExecutionEnvironmentBalanceTooLow();

    // Atlas
    error PreOpsFail();
    error UserOpFail();
    // error SolverFail(); // Only sim version of err is used
    error PostOpsFail();
    error InvalidAccess();

    // Escrow
    error UncoveredResult();

    // AtlETH
    error InsufficientUnbondedBalance(uint256 balance, uint256 requested);
    error InsufficientBondedBalance(uint256 balance, uint256 requested);
    error PermitDeadlineExpired();
    error InvalidSigner();
    error EscrowLockActive();
    error InsufficientWithdrawableBalance(uint256 balance, uint256 requested);
    error InsufficientAvailableBalance(uint256 balance, uint256 requested);
    error InsufficientSurchargeBalance(uint256 balance, uint256 requested);
    error InsufficientBalanceForDeduction(uint256 balance, uint256 requested);
    error ValueTooLarge();
    error BidTooHigh(uint256 indexInSolverOps, uint256 bidAmount);

    // DAppIntegration
    error OnlyGovernance();
    error SignatoryActive();
    error InvalidCaller();
    error InvalidDAppControl();
    error DAppNotEnabled();
    error AtlasLockActive();

    // Permit69
    error InvalidEnvironment();
    error EnvironmentMismatch();
    error InvalidLockState();

    // GasAccounting
    error LedgerFinalized(uint8 id);
    error LedgerBalancing(uint8 id);
    error MissingFunds(uint8 id);
    error InsufficientFunds();
    error NoUnfilledRequests();
    error SolverMustReconcile();
    error DoubleReconcile();
    error InvalidExecutionEnvironment(address correctEnvironment);
    error InvalidSolverFrom(address solverFrom);
    error InsufficientSolverBalance(uint256 actual, uint256 msgValue, uint256 holds, uint256 needed);
    error InsufficientAtlETHBalance(uint256 actual, uint256 needed);
    error InsufficientTotalBalance(uint256 shortfall);
    error UnbalancedAccounting();

    // SafetyLocks
    error NotInitialized();
    error AlreadyInitialized();

    // AtlasVerification
    error NoUnusedNonceInBitmap();

    // DAppControl
    error BothUserAndDAppNoncesCannotBeSequential();
    error InvalidControl();
    error NoDelegatecall();
    error MustBeDelegatecalled();
    error OnlyAtlas();
    error WrongPhase();
    error WrongDepth();
    error InsufficientLocalFunds();
    error NotImplemented();
}
