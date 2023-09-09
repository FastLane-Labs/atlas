//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/EscrowTypes.sol";

library EscrowBits {
    uint256 public constant SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 public constant VALIDATION_GAS_LIMIT = 500_000;
    uint256 public constant SEARCHER_GAS_BUFFER = 5; // out of 100
    uint256 public constant FASTLANE_GAS_BUFFER = 125_000; // integer amount

    uint256 internal constant _EXECUTION_REFUND = (
        1 << uint256(SearcherOutcome.CallReverted) | 1 << uint256(SearcherOutcome.BidNotPaid)
            | 1 << uint256(SearcherOutcome.CallValueTooHigh) | 1 << uint256(SearcherOutcome.UnknownError)
            | 1 << uint256(SearcherOutcome.CallbackFailed) | 1 << uint256(SearcherOutcome.IntentUnfulfilled)
            | 1 << uint256(SearcherOutcome.EVMError) | 1 << uint256(SearcherOutcome.SearcherStagingFailed)
            | 1 << uint256(SearcherOutcome.Success)
    );

    uint256 internal constant _NO_NONCE_UPDATE = (
        1 << uint256(SearcherOutcome.InvalidSignature) | 1 << uint256(SearcherOutcome.AlreadyExecuted)
            | 1 << uint256(SearcherOutcome.InvalidNonceUnder)
    );

    uint256 internal constant _EXECUTED_WITH_ERROR = (
        1 << uint256(SearcherOutcome.CallReverted) | 1 << uint256(SearcherOutcome.BidNotPaid)
            | 1 << uint256(SearcherOutcome.CallValueTooHigh) | 1 << uint256(SearcherOutcome.UnknownError)
            | 1 << uint256(SearcherOutcome.CallbackFailed) | 1 << uint256(SearcherOutcome.IntentUnfulfilled)
            | 1 << uint256(SearcherOutcome.SearcherStagingFailed) | 1 << uint256(SearcherOutcome.EVMError) 
    );

    uint256 internal constant _EXECUTED_SUCCESSFULLY = (1 << uint256(SearcherOutcome.Success));

    uint256 internal constant _NO_USER_REFUND = (
        1 << uint256(SearcherOutcome.InvalidSignature) | 1 << uint256(SearcherOutcome.InvalidUserHash)
            | 1 << uint256(SearcherOutcome.InvalidBidsHash) | 1 << uint256(SearcherOutcome.GasPriceOverCap)
            | 1 << uint256(SearcherOutcome.InvalidSequencing) | 1 << uint256(SearcherOutcome.InvalidControlHash)
    );

    uint256 internal constant _CALLDATA_REFUND = (
        1 << uint256(SearcherOutcome.InsufficientEscrow) | 1 << uint256(SearcherOutcome.InvalidNonceOver)
            | 1 << uint256(SearcherOutcome.UserOutOfGas) | 1 << uint256(SearcherOutcome.CallValueTooHigh)
    );

    uint256 internal constant _FULL_REFUND = (
        _EXECUTION_REFUND | 1 << uint256(SearcherOutcome.AlreadyExecuted)
            | 1 << uint256(SearcherOutcome.InvalidNonceUnder) | 1 << uint256(SearcherOutcome.PerBlockLimit)
            | 1 << uint256(SearcherOutcome.InvalidFormat)
    );

    function canExecute(uint256 result) internal pure returns (bool) {
        return ((result >> 1) == 0);
    }

    function executionSuccessful(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_SUCCESSFULLY) != 0;
    }

    function executedWithError(uint256 result) internal pure returns (bool) {
        return (result & _EXECUTED_WITH_ERROR) != 0;
    }

    function updateEscrow(uint256 result) internal pure returns (bool) {
        return !((result & _NO_NONCE_UPDATE != 0) || (result & _NO_USER_REFUND != 0));
    }
}
