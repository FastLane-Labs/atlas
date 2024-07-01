// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";
import "src/contracts/types/EscrowTypes.sol";
import "../base/TestUtils.sol";

contract EscrowBitsTest is Test {
    using EscrowBits for uint256;

    function testConstants() public pure {
        string memory expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111111";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._NO_REFUND),
            expectedBitMapString,
            "_NO_REFUND incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111111110000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._PARTIAL_REFUND),
            expectedBitMapString,
            "_PARTIAL_REFUND incorrect"
        );

        expectedBitMapString =
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111110000000000000000";
        assertEq(
            TestUtils.uint256ToBinaryString(EscrowBits._FULL_REFUND), expectedBitMapString, "_FULL_REFUND incorrect"
        );
    }

    function testLogEscrowConstants() public view {
        console.log("EscrowBits._NO_REFUND", EscrowBits._NO_REFUND);
        console.log("EscrowBits._NO_REFUND", EscrowBits._PARTIAL_REFUND);
        console.log("EscrowBits._NO_REFUND", EscrowBits._FULL_REFUND);
    }

    function testCanExecute() public pure {
        uint256 valid = 0;
        assertEq(valid.canExecute(), true);

        uint256 invalid = 1 << 1;
        assertEq(invalid.canExecute(), false);
        invalid = 1 << 2;
        assertEq(invalid.canExecute(), false);
    }

    function testExecutionSuccessful() public pure {
        uint256 valid = 0;
        assertEq(valid.executionSuccessful(), true);

        uint256 invalid = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidUserHash);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.AlteredControl);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.GasPriceOverCap);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.UserOutOfGas);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.InsufficientEscrow);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.PerBlockLimit);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.SolverOpReverted);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.BidNotPaid);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.PreSolverFailed);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.CallValueTooHigh);
        assertEq(invalid.executionSuccessful(), false);
        invalid = 1 << uint256(SolverOutcome.EVMError);
        assertEq(invalid.executionSuccessful(), false);
    }

    function testExecutedWithError() public pure {
        uint256 valid = 1 << uint256(SolverOutcome.SolverOpReverted);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.BidNotPaid);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.CallValueTooHigh);
        assertEq(valid.executedWithError(), false);
        valid = 1 << uint256(SolverOutcome.PreSolverFailed);
        assertEq(valid.executedWithError(), false);
        valid = 1 << uint256(SolverOutcome.BalanceNotReconciled);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.CallbackNotCalled);
        assertEq(valid.executedWithError(), true);
        valid = 1 << uint256(SolverOutcome.EVMError);
        assertEq(valid.executedWithError(), true);

        uint256 invalid = 0;
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidUserHash);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.AlteredControl);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.GasPriceOverCap);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.UserOutOfGas);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.InsufficientEscrow);
        assertEq(invalid.executedWithError(), false);
        invalid = 1 << uint256(SolverOutcome.PerBlockLimit);
        assertEq(invalid.executedWithError(), false);
    }

    function testUpdateEscrow() public pure {
        uint256 valid = 0;
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.UserOutOfGas);
        assertEq(valid.updateEscrow(), false);
        valid = 1 << uint256(SolverOutcome.InsufficientEscrow);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.PerBlockLimit);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.SolverOpReverted);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.BidNotPaid);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.PreSolverFailed);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.CallValueTooHigh);
        assertEq(valid.updateEscrow(), true);
        valid = 1 << uint256(SolverOutcome.EVMError);
        assertEq(valid.updateEscrow(), true);

        uint256 invalid = 1 << uint256(SolverOutcome.InvalidSignature);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.InvalidUserHash);
        assertEq(invalid.updateEscrow(), false);
        invalid = 1 << uint256(SolverOutcome.GasPriceOverCap);
        assertEq(invalid.updateEscrow(), true);
        invalid = 1 << uint256(SolverOutcome.AlteredControl);
        assertEq(invalid.updateEscrow(), false);
    }
}
