// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {SafetyBits} from "../../src/contracts/libraries/SafetyBits.sol";
import "../../src/contracts/types/LockTypes.sol";
import "../base/TestUtils.sol";

contract SafetyBitsTest is Test {
    using SafetyBits for EscrowKey;

    function initializeEscrowLock() public pure returns (EscrowKey memory key) {
        key = key.initializeEscrowLock(true, 1, address(0));
    }

    function testConstants() public {
        string memory expectedBitMapString = "0010000010001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_SEARCHERS_X_REQUESTED),
            expectedBitMapString,
            "_LOCKED_X_SEARCHERS_X_REQUESTED incorrect"
        );

        expectedBitMapString = "0100000010001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_SEARCHERS_X_VERIFIED),
            expectedBitMapString,
            "_LOCKED_X_SEARCHERS_X_VERIFIED incorrect"
        );

        expectedBitMapString = "0001000000100100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_STAGING_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_STAGING_X_UNSET incorrect"
        );

        expectedBitMapString = "0001100000000010";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._PENDING_X_RELEASING_X_UNSET),
            expectedBitMapString,
            "_PENDING_X_RELEASING_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000000101000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_STAGING_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_STAGING_X_UNSET incorrect"
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
            TestUtils.uint16ToBinaryString(SafetyBits._PENDING_X_SEARCHER_X_UNSET),
            expectedBitMapString,
            "_PENDING_X_SEARCHER_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000010000010";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_SEARCHER_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_SEARCHER_X_UNSET incorrect"
        );

        expectedBitMapString = "0001000100001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCK_PAYMENTS), expectedBitMapString, "_LOCK_PAYMENTS incorrect"
        );

        expectedBitMapString = "0001010000000100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._NO_SEARCHER_SUCCESS),
            expectedBitMapString,
            "_NO_SEARCHER_SUCCESS incorrect"
        );

        expectedBitMapString = "0001001000000010";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_REFUND_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_REFUND_X_UNSET incorrect"
        );

        expectedBitMapString = "0001010000001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_VERIFICATION_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_VERIFICATION_X_UNSET incorrect"
        );
    }

    function testInitializeEscrowLock() public {
        EscrowKey memory key = initializeEscrowLock();
        assertTrue(key.approvedCaller == address(0));
        assertTrue(key.makingPayments == false);
        assertTrue(key.paymentsComplete == false);
        assertTrue(key.callIndex == 0);
        assertTrue(key.callMax == 4);
        assertTrue(key.lockState == SafetyBits._ACTIVE_X_STAGING_X_UNSET);
        assertTrue(key.gasRefund == 0);
    }

    function testPack() public {
        EscrowKey memory key = initializeEscrowLock();
        bytes32 want = 0x0000000000000000000000000000000000000000000000041024000000000000;
        assertTrue(key.pack() == want);
    }

    function testHoldVerificationLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdVerificationLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_VERIFICATION_X_UNSET);
        assertTrue(key.approvedCaller == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testSetAllSearchersFailed() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.setAllSearchersFailed();
        assertTrue(key.lockState == SafetyBits._NO_SEARCHER_SUCCESS);
        assertTrue(key.approvedCaller == address(0));
        assertTrue(key.callIndex == 3);
    }

    function testAllocationComplete() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.allocationComplete();
        assertTrue(key.makingPayments == false);
        assertTrue(key.paymentsComplete == true);
    }

    function testTurnSearcherLockPayments() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.turnSearcherLockPayments(address(1));
        assertTrue(key.makingPayments == true);
        assertTrue(key.lockState == SafetyBits._LOCK_PAYMENTS);
        assertTrue(key.approvedCaller == address(1));
    }

    function testHoldSearcherLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdSearcherLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_SEARCHERS_X_REQUESTED);
        assertTrue(key.approvedCaller == address(1));
    }

    function testHoldUserLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdUserLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_USER_X_UNSET);
        assertTrue(key.approvedCaller == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testHoldStagingLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdStagingLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_STAGING_X_UNSET);
        assertTrue(key.approvedCaller == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testTurnSearcherLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.turnSearcherLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_SEARCHERS_X_VERIFIED);
        assertTrue(key.approvedCaller == address(1));
    }
}
