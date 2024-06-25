//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/// @title ValidCallsResult
/// @notice Enum for ValidCallsResult
/// @dev A single ValidCallsResult is returned by `validateCalls` in AtlasVerification
enum ValidCallsResult {
    Valid,
    GasPriceHigherThanMax,
    TxValueLowerThanCallValue,
    DAppSignatureInvalid,
    UserSignatureInvalid,
    TooManySolverOps,
    UserDeadlineReached,
    DAppDeadlineReached,
    ExecutionEnvEmpty,
    NoSolverOp,
    UnknownAuctioneerNotAllowed,
    InvalidSequence,
    InvalidAuctioneer,
    InvalidBundler,
    OpHashMismatch,
    DeadlineMismatch,
    InvalidControl,
    InvalidSolverGasLimit,
    InvalidDAppNonce,
    CallConfigMismatch,
    DAppToInvalid,
    UserFromInvalid,
    ControlMismatch,
    UserNonceInvalid,
    InvalidCallChainHash,
    DAppNotEnabled,
    BothUserAndDAppNoncesCannotBeSequential,
    InvertBidValueCannotBeExPostBids
}
