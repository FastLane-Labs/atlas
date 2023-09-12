// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {SafetyBits} from "../../src/contracts/libraries/SafetyBits.sol";
import "../../src/contracts/types/LockTypes.sol";

contract SafetyBitsTest is Test {
    using SafetyBits for EscrowKey;

    function initializeEscrowLock() public pure returns (EscrowKey memory key) {
        key = key.initializeEscrowLock(true, 1, address(0));
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
        assertTrue(key.lockState == SafetyBits._LOCKED_X_SEARCHERS_X_REQUESTED);
        assertTrue(key.approvedCaller == address(1));
    }
}
