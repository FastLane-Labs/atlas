//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/ValidCallsTypes.sol";

contract AtlasErrors {
    error UserSimulationFailed();
    error UserSimulationSucceeded();
    error UserUnexpectedSuccess();
    
    error SolverBidUnpaid();
    error SolverMsgValueUnpaid();
    error SolverOperationReverted();
    error SolverEVMError();
    error AlteredUserHash();
    error AlteredControlHash();
    error InvalidSolverHash();
    error HashChainBroken();
    error IntentUnfulfilled();
    error PreSolverFailed();
    error PostSolverFailed();

    error UserNotFulfilled();
    error NoAuctionWinner();

    error VerificationSimFail();
    error PreOpsSimFail();
    error UserOpSimFail();
    error SolverSimFail();
    error PostOpsSimFail();
    error SimulationPassed();
    error ValidCalls(ValidCallsResult);


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

    event Bond(address indexed owner, uint256 amount);
    event Unbond(address indexed owner, uint256 amount, uint256 earliestAvailable);
    event Redeem(address indexed owner, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // DAppIntegration
    error OnlyGovernance();
    error OwnerActive();
    error SignatoryActive();
    error InvalidCaller();
    error InvalidDAppControl();
    error DAppNotEnabled();

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
    error OnlyAccount();
}

contract AtlasEvents {
    // Metacall events
    event MetacallResult(address indexed bundler, address indexed user, address indexed winningSolver);
    event SolverExecution(address indexed solver, uint256 index, bool isWin);

    // Escrow call step events
    event PreOpsCall(address environment, bool success, bytes returnData);
    event UserCall(address environment, bool success, bytes returnData);
    event PostOpsCall(address environment, bool success); // No return data tracking for post ops?

    // Factory
    event ExecutionEnvironmentCreated(address indexed user, address indexed executionEnvironment);

    // Gas accounting
    event GasRefundSettled(address indexed bundler, uint256 refundedETH);

    // Surcharge events
    event SurchargeWithdrawn(address to, uint256 amount);
    event SurchargeRecipientTransferStarted(address currentRecipient, address newRecipient);
    event SurchargeRecipientTransferred(address newRecipient);

    event SolverTxResult(
        address indexed solverTo, address indexed solverFrom, bool executed, bool success, uint256 result
    );
    event UserTxResult(address indexed user, uint256 valueReturned, uint256 gasRefunded);
    event MEVPaymentFailure(address indexed controller, uint32 callConfig, address bidToken, uint256 bidAmount);
}
