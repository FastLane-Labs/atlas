//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "../types/ValidCallsTypes.sol";

error UserSimulationFailed();
error UserSimulationSucceeded();
error UserUnexpectedSuccess();

contract FastLaneErrorsEvents {
    // NOTE: nonce is the executed nonce
    event SolverTxResult(
        address indexed solverTo, address indexed solverFrom, bool executed, bool success, uint256 result
    );

    event UserTxResult(address indexed user, uint256 valueReturned, uint256 gasRefunded);

    event MEVPaymentFailure(address indexed controller, uint32 callConfig, address bidToken, uint256 bidAmount);

    error SolverBidUnpaid();
    error SolverFailedCallback();
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

    // NEW Custom Errors to replace string errors

    // NEW - Atlas
    error PreOpsFail();
    error UserOpFail();
    // error SolverFail(); // Only sim version of err is used
    error PostOpsFail();
    error RevertToReuse();
    error InvalidAccess();

    // NEW - Escrow
    error UncoveredResult();

    // NEW - AtlETH
    error InsufficientBalance();
    error PermitDeadlineExpired();
    error InvalidSigner();
    error EscrowLockActive();

    // NEW - DAppIntegration
    error OnlyGovernance();
    error OwnerActive();
    error SignatoryActive();
    error InvalidCaller();
    error InvalidDAppControl();
    error DAppNotEnabled();

    // NEW - Permit69
    error InvalidEnvironment();
    error EnvironmentMismatch();
    error InvalidLockState();

    // NEW - GasAccounting
    error LedgerFinalized(uint8 id);
    error LedgerBalancing(uint8 id);
    error MissingFunds(uint8 id);
    error InsufficientFunds();
    error NoUnfilledRequests();
    error SolverMustReconcile();
    error GasAccountingLibError();

    // NEW - SafetyLocks
    error NotInitialized();
    error AlreadyInitialized();
    error SafetyLocksLibError();

    /*
    event NewDAppIntegration(
        address indexed environment,
        address indexed user,
        address indexed controller,
        uint32 callConfig
    );

    event DAppDisabled(
        address indexed environment,
        address indexed user,
        address indexed controller,
        uint32 callConfig
    );
    */
}
