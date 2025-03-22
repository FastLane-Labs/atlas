//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./ValidCalls.sol";

contract AtlasErrors {
    // Simulator
    error SimulatorBalanceTooLow();
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

    error InvalidSolver();
    error BidNotPaid();
    error InvertedBidExceedsCeiling();
    error BalanceNotReconciled();
    error SolverOpReverted();
    error AlteredControl();
    error InvalidEntry();
    error CallbackNotCalled();
    error PreSolverFailed();
    error PostSolverFailed();
    error InsufficientEscrow();

    error VerificationSimFail(ValidCallsResult);
    error PreOpsSimFail();
    error UserOpSimFail();
    error SolverSimFail(uint256 solverOutcomeResult); // uint param is result returned in `verifySolverOp`
    error AllocateValueSimFail();
    error ValidCalls(ValidCallsResult);
    error InsufficientGasForMetacallSimulation(uint256 estimatedMetacallGas, uint256 suggestedSimGas);

    // Execution Environment
    error InvalidUser();
    error InvalidTo();
    error InvalidCodeHash();
    error PreOpsDelegatecallFail();
    error UserOpValueExceedsBalance();
    error UserWrapperDelegatecallFail();
    error UserWrapperCallFail();
    error AllocateValueDelegatecallFail();
    error NotEnvironmentOwner();
    error ExecutionEnvironmentBalanceTooLow();

    // Atlas
    error PreOpsFail();
    error UserOpFail();
    error AllocateValueFail();
    error InvalidAccess();

    // Escrow
    error UncoveredResult();
    error InvalidEscrowDuration();
    error DAppGasLimitReached();

    // AtlETH
    error EscrowLockActive();
    error InsufficientBalanceForDeduction(uint256 balance, uint256 requested);

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
    error InvalidExecutionEnvironment(address correctEnvironment);
    error InsufficientAtlETHBalance(uint256 actual, uint256 needed);
    error InsufficientTotalBalance(uint256 shortfall);
    error BorrowsNotRepaid(uint256 borrows, uint256 repays);
    error AssignDeficitTooLarge(uint256 deficit, uint256 bundlerRefund);

    // SafetyLocks
    error NotInitialized();
    error AlreadyInitialized();

    // Storage
    error SurchargeRateTooHigh();

    // AtlasVerification
    error NoUnusedNonceInBitmap();

    // DAppControl
    error BothUserAndDAppNoncesCannotBeSequential();
    error BothPreOpsAndUserReturnDataCannotBeTracked();
    error InvalidControl();
    error NoDelegatecall();
    error MustBeDelegatecalled();
    error OnlyAtlas();
    error WrongPhase();
    error WrongDepth();
    error InsufficientLocalFunds();
    error NotImplemented();
    error InvertBidValueCannotBeExPostBids();
    error ExPostBidsAndMultipleSuccessfulSolversNotSupportedTogether();
    error InvertsBidValueAndMultipleSuccessfulSolversNotSupportedTogether();
    error NeedSolversForMultipleSuccessfulSolvers();
    error SolverCannotBeAuctioneerForMultipleSuccessfulSolvers();
    error CannotRequireFulfillmentForMultipleSuccessfulSolvers();
}
