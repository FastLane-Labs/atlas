// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { SafetyBits } from "../../src/contracts/libraries/SafetyBits.sol";
import "../../src/contracts/types/LockTypes.sol";
import "../base/TestUtils.sol";

contract SafetyBitsTest is Test {
    using SafetyBits for EscrowKey;

    function initializeEscrowLock() public pure returns (EscrowKey memory key) {
        key = key.initializeEscrowLock(true, 1, address(0), false);
    }

    // TODO Let's fix the constants test last.
    /*
    function testConstants() public {
        string memory expectedBitMapString = "0010000010001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_SOLVERS_X_REQUESTED),
            expectedBitMapString,
            "_LOCKED_X_SOLVERS_X_REQUESTED incorrect"
        );

        expectedBitMapString = "0100000010001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_SOLVERS_X_VERIFIED),
            expectedBitMapString,
            "_LOCKED_X_SOLVERS_X_VERIFIED incorrect"
        );

        expectedBitMapString = "0001000000100100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_PRE_OPS_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_PRE_OPS_X_UNSET incorrect"
        );

        expectedBitMapString = "0001100000000010";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._PENDING_X_RELEASING_X_UNSET),
            expectedBitMapString,
            "_PENDING_X_RELEASING_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000000101000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_PRE_OPS_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_PRE_OPS_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000001000100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_USER_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_USER_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000001001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_USER_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_USER_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000010000010";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._PENDING_X_SOLVER_X_UNSET),
            expectedBitMapString,
            "_PENDING_X_SOLVER_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000010000010";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_SOLVER_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_SOLVER_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000100001000";
        assertEq(
    TestUtils.uint16ToBinaryString(SafetyBits._LOCK_PAYMENTS), expectedBitMapString, "_LOCK_PAYMENTS incorrect"
        );

        expectedBitMapString = "0001010000000100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._NO_SOLVER_SUCCESS),
            expectedBitMapString,
            "_NO_SOLVER_SUCCESS incorrect"
        );

        expectedBitMapString = "0001010000001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_VERIFICATION_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_VERIFICATION_X_UNSET incorrect"
        );
    }
    */

    function testInitializeEscrowLock() public {
        EscrowKey memory key = initializeEscrowLock();
        assertTrue(key.approvedCaller == address(0));
        assertTrue(key.makingPayments == false);
        assertTrue(key.paymentsComplete == false);
        assertTrue(key.callIndex == 0);
        assertTrue(key.callMax == 4);
        assertTrue(key.lockState == SafetyBits._ACTIVE_X_PRE_OPS_X_UNSET);
        assertTrue(key.gasRefund == 0);
    }

    function testPack() public {
        EscrowKey memory key = initializeEscrowLock();
        bytes32 want = 0x0000000000000000000000000000000000000000000000040024000000000001;
        bytes32 packed = key.pack();
        // console.logBytes32(packed);
        assertTrue(packed == want);
    }

    function testHoldDAppOperationLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdDAppOperationLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_VERIFICATION_X_UNSET);
        assertTrue(key.approvedCaller == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testSetAllSolversFailed() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.setAllSolversFailed();
        assertTrue(key.lockState == SafetyBits._NO_SOLVER_SUCCESS);
        assertTrue(key.approvedCaller == address(0));
        assertTrue(key.callIndex == 3);
    }

    function testAllocationComplete() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.allocationComplete();
        assertTrue(key.makingPayments == false);
        assertTrue(key.paymentsComplete == true);
    }

    function testTurnSolverLockPayments() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.turnSolverLockPayments(address(1));
        assertTrue(key.makingPayments == true);
        assertTrue(key.lockState == SafetyBits._LOCK_PAYMENTS);
        assertTrue(key.approvedCaller == address(1));
    }

    function testHoldSolverLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdSolverLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_SOLVERS_X_REQUESTED);
        assertTrue(key.approvedCaller == address(1));
    }

    function testHoldUserLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdUserLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_USER_X_UNSET);
        assertTrue(key.approvedCaller == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testHoldPreOpsLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdPreOpsLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_PRE_OPS_X_UNSET);
        assertTrue(key.approvedCaller == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testTurnSolverLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.turnSolverLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_SOLVERS_X_VERIFIED);
        assertTrue(key.approvedCaller == address(1));
    }
}
