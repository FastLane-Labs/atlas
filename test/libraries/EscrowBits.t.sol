// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {EscrowBits} from "../../src/contracts/libraries/EscrowBits.sol";
import "../../src/contracts/types/EscrowTypes.sol";

contract EscrowBitsTest is Test {
    using EscrowBits for uint256;

    function testCanExecute() public {
        uint256 valid = 0;
        assertEq(valid.canExecute(), true);
        valid = 1;
        assertEq(valid.canExecute(), true);

        uint256 invalid = 1 << 1;
        assertEq(invalid.canExecute(), false);
        invalid = 1 << 2;
        assertEq(invalid.canExecute(), false);
    }

    function testExecutionSuccessful() public {
        uint256 valid = 1 << uint256(SearcherOutcome.Success);
        assertEq(valid.executionSuccessful(), true);

        uint256 invalid = 1 << uint256(SearcherOutcome.PendingUpdate);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.ExecutionCompleted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.UpdateCompleted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.BlockExecution);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidSignature);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidUserHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidControlHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidBidsHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidSequencing);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.GasPriceOverCap);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.UserOutOfGas);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InsufficientEscrow);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidNonceOver);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.AlreadyExecuted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidNonceUnder);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.PerBlockLimit);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidFormat);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.LostAuction);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.UnknownError);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.CallReverted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.BidNotPaid);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.IntentUnfulfilled);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.SearcherStagingFailed);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.CallValueTooHigh);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.CallbackFailed);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SearcherOutcome.EVMError);
        assertEq(invalid.executionSuccessful(), false);
    }

    function testExecutedWithError() public {
        uint256 valid = 1 << uint256(SearcherOutcome.CallReverted);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.BidNotPaid);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.CallValueTooHigh);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.UnknownError);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.CallbackFailed);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.IntentUnfulfilled);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.SearcherStagingFailed);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SearcherOutcome.EVMError);
        assertEq(valid.executedWithError(), true);

        uint256 invalid = 1 << uint256(SearcherOutcome.Success);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.PendingUpdate);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.ExecutionCompleted);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.UpdateCompleted);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.BlockExecution);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidSignature);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidUserHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidControlHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidBidsHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidSequencing);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.GasPriceOverCap);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.UserOutOfGas);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InsufficientEscrow);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidNonceOver);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.AlreadyExecuted);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidNonceUnder);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.PerBlockLimit);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidFormat);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SearcherOutcome.LostAuction);
        assertEq(invalid.executedWithError(), false);
    }

    function testUpdateEscrow() public {
        uint256 valid = 1 << uint256(SearcherOutcome.Success);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.PendingUpdate);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.ExecutionCompleted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.UpdateCompleted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.BlockExecution);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.UserOutOfGas);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.InsufficientEscrow);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.InvalidNonceOver);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.PerBlockLimit);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.InvalidFormat);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.LostAuction);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.UnknownError);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.CallReverted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.BidNotPaid);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.IntentUnfulfilled);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.SearcherStagingFailed);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.CallValueTooHigh);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.CallbackFailed);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SearcherOutcome.EVMError);
        assertEq(valid.updateEscrow(), true);

        uint256 invalid = 1 << uint256(SearcherOutcome.InvalidSignature);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.AlreadyExecuted);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidNonceUnder);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidUserHash);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidBidsHash);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.GasPriceOverCap);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidSequencing);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SearcherOutcome.InvalidControlHash);
        assertEq(invalid.updateEscrow(), false);
    }
}
