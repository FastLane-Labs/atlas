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
