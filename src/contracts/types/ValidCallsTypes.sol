//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/// @title ValidCallsResult
/// @notice Enum for ValidCallsResult
/// @dev A single ValidCallsResult is returned by `validateCalls` in AtlasVerification
enum ValidCallsResult {
    Valid,
    // Results below will cause metacall to revert
    UserFromInvalid,
    UserSignatureInvalid,
    DAppSignatureInvalid,
    UserNonceInvalid,
    InvalidDAppNonce,
    UnknownAuctioneerNotAllowed,
    InvalidAuctioneer,
    InvalidBundler,
    InvertBidValueCannotBeExPostBids,
    GRACEFUL_RETURN_THRESHOLD, // Do not use this value as a result
    // Results below will cause metacall to gracefully return
    GasPriceHigherThanMax,
    TxValueLowerThanCallValue,
    TooManySolverOps,
    UserDeadlineReached,
    DAppDeadlineReached,
    ExecutionEnvEmpty,
    NoSolverOp,
    InvalidSequence,
    OpHashMismatch,
    DeadlineMismatch,
    InvalidControl,
    InvalidSolverGasLimit,
    InvalidCallConfig,
    CallConfigMismatch,
    DAppToInvalid,
    UserToInvalid,
    ControlMismatch,
    InvalidCallChainHash,
    DAppNotEnabled,
    BothUserAndDAppNoncesCannotBeSequential
}
