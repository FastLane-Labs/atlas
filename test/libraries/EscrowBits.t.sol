// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {EscrowBits} from "../../src/contracts/libraries/EscrowBits.sol";
import "../../src/contracts/types/EscrowTypes.sol";
import "../base/TestUtils.sol";

contract EscrowBitsTest is Test {
    using EscrowBits for uint256;

    function testConstants() public {
        string memory expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111111110000000000000000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._EXECUTION_REFUND),
            expectedBitMapString,
            "_EXECUTION_REFUND incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001100000000100000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._NO_NONCE_UPDATE),
            expectedBitMapString,
            "_NO_NONCE_UPDATE incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111110000000000000000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._EXECUTED_WITH_ERROR),
            expectedBitMapString,
            "_EXECUTED_WITH_ERROR incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._EXECUTED_SUCCESSFULLY),
            expectedBitMapString,
            "_EXECUTED_SUCCESSFULLY incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011111110000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._NO_USER_REFUND),
            expectedBitMapString,
            "_NO_USER_REFUND incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000011100000000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._CALLDATA_REFUND),
            expectedBitMapString,
            "_CALLDATA_REFUND incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111111110111100000000000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._FULL_REFUND), expectedBitMapString, "_FULL_REFUND incorrect"
        );
    }

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
        uint256 valid = 1 << uint256(SolverOutcome.Success);
        assertEq(valid.executionSuccessful(), true);

        uint256 invalid = 1 << uint256(SolverOutcome.PendingUpdate);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.ExecutionCompleted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.UpdateCompleted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.BlockExecution);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidUserHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidControlHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidBidsHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidSequencing);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.GasPriceOverCap);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.UserOutOfGas);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InsufficientEscrow);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidNonceOver);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.AlreadyExecuted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidNonceUnder);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.PerBlockLimit);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidFormat);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.LostAuction);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.UnknownError);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.CallReverted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.BidNotPaid);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.IntentUnfulfilled);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.PreSolverFailed);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.CallValueTooHigh);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.CallbackFailed);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.EVMError);
        assertEq(invalid.executionSuccessful(), false);
    }

    function testExecutedWithError() public {
        uint256 valid = 1 << uint256(SolverOutcome.CallReverted);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.BidNotPaid);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.CallValueTooHigh);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.UnknownError);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.CallbackFailed);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.IntentUnfulfilled);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.PreSolverFailed);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.EVMError);
        assertEq(valid.executedWithError(), true);

        uint256 invalid = 1 << uint256(SolverOutcome.Success);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.PendingUpdate);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.ExecutionCompleted);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.UpdateCompleted);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.BlockExecution);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidUserHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidControlHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidBidsHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidSequencing);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.GasPriceOverCap);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.UserOutOfGas);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InsufficientEscrow);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidNonceOver);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.AlreadyExecuted);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidNonceUnder);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.PerBlockLimit);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidFormat);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.LostAuction);
        assertEq(invalid.executedWithError(), false);
    }

    function testUpdateEscrow() public {
        uint256 valid = 1 << uint256(SolverOutcome.Success);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.PendingUpdate);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.ExecutionCompleted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.UpdateCompleted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.BlockExecution);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.UserOutOfGas);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.InsufficientEscrow);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.InvalidNonceOver);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.PerBlockLimit);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.InvalidFormat);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.LostAuction);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.UnknownError);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.CallReverted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.BidNotPaid);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.IntentUnfulfilled);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.PreSolverFailed);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.CallValueTooHigh);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.CallbackFailed);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.EVMError);
        assertEq(valid.updateEscrow(), true);

        uint256 invalid = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.AlreadyExecuted);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidNonceUnder);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidUserHash);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidBidsHash);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.GasPriceOverCap);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidSequencing);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidControlHash);
        assertEq(invalid.updateEscrow(), false);
    }
}
