// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";
import "src/contracts/types/LockTypes.sol";
import "../base/TestUtils.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";

import { EXECUTION_PHASE_OFFSET } from "src/contracts/libraries/SafetyBits.sol";


contract SafetyBitsTest is Test {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;

    uint16 internal constant _ACTIVE_X_PRE_OPS_X_UNSET =
        uint16(1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps)));

    uint16 internal constant _ACTIVE_X_USER_X_UNSET =
        uint16(1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation)));


    function initializeEscrowLock() public view returns (EscrowKey memory key) {
        key = _buildEscrowLock(0, address(0), bytes32(0), address(0), 1, false);
    }

    function _buildEscrowLock(
        uint32 callConfig,
        address executionEnvironment,
        bytes32 userOpHash,
        address bundler,
        uint8 solverOpCount,
        bool isSimulation
    )
        internal
        view
        returns (EscrowKey memory)
    {
        bool needsPreOps = callConfig.needsPreOpsCall();
        
        return EscrowKey({
            executionEnvironment: executionEnvironment,
            userOpHash: userOpHash,
            bundler: bundler,
            addressPointer: executionEnvironment,
            solverSuccessful: false,
            paymentsSuccessful: false,
            callIndex: needsPreOps ? 0 : 1,
            callCount: solverOpCount + 3,
            lockState: needsPreOps ? _ACTIVE_X_PRE_OPS_X_UNSET : _ACTIVE_X_USER_X_UNSET,
            solverOutcome: 0,
            bidFind: false,
            isSimulation: isSimulation,
            callDepth: 0
        });
    }

    function testConstants() public {
        string memory expectedBitMapString = "0000000100001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_SOLVERS_X_REQUESTED),
            expectedBitMapString,
            "_LOCKED_X_SOLVERS_X_REQUESTED incorrect"
        );

        expectedBitMapString = "0000000000100100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_PRE_OPS_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_PRE_OPS_X_UNSET incorrect"
        );

        expectedBitMapString = "0000000000101000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_PRE_OPS_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_PRE_OPS_X_UNSET incorrect"
        );

        expectedBitMapString = "0000000001000100";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._ACTIVE_X_USER_X_UNSET),
            expectedBitMapString,
            "_ACTIVE_X_USER_X_UNSET incorrect"
        );

        expectedBitMapString = "0000000001001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_USER_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_USER_X_UNSET incorrect"
        );

        expectedBitMapString = "0000010000001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCK_PAYMENTS), expectedBitMapString, "_LOCK_PAYMENTS incorrect"
        );

        expectedBitMapString = "0000100000001000";
        assertEq(
            TestUtils.uint16ToBinaryString(SafetyBits._LOCKED_X_VERIFICATION_X_UNSET),
            expectedBitMapString,
            "_LOCKED_X_VERIFICATION_X_UNSET incorrect"
        );
    }

    function testInitializeEscrowLock() public {
        EscrowKey memory key = initializeEscrowLock();
        assertTrue(key.addressPointer == address(0));
        assertTrue(key.solverSuccessful == false);
        assertTrue(key.paymentsSuccessful == false);
        assertTrue(key.callIndex == 0);
        assertTrue(key.callCount == 4);
        assertTrue(key.lockState == SafetyBits._ACTIVE_X_PRE_OPS_X_UNSET);
        assertTrue(key.solverOutcome == 0);
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
        key.addressPointer = address(1);
        key.callCount = 4;
        key.callIndex = 2;
        key = key.holdPostOpsLock();
        assertTrue(key.lockState == SafetyBits._LOCKED_X_VERIFICATION_X_UNSET);
        assertFalse(key.addressPointer == address(1));
        assertTrue(key.callIndex == 3);

        EscrowKey memory newKey = initializeEscrowLock();
        newKey.addressPointer = address(1);
        newKey.solverSuccessful = true;
        newKey.callCount = 4;
        newKey.callIndex = 2;
        newKey = newKey.holdPostOpsLock();
        assertTrue(newKey.addressPointer == address(1));
        assertTrue(newKey.callIndex == 3);
    }

    function testTurnSolverLockPayments() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdAllocateValueLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCK_PAYMENTS);
        assertTrue(key.addressPointer == address(1));
    }

    function testHoldSolverLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdSolverLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_SOLVERS_X_REQUESTED);
        assertTrue(key.addressPointer == address(1));
    }

    function testHoldUserLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdUserLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_USER_X_UNSET);
        assertTrue(key.addressPointer == address(1));
        assertTrue(key.callIndex == 1);
    }

    function testHoldPreOpsLock() public {
        EscrowKey memory key = initializeEscrowLock();
        key = key.holdPreOpsLock(address(1));
        assertTrue(key.lockState == SafetyBits._LOCKED_X_PRE_OPS_X_UNSET);
        assertTrue(key.addressPointer == address(1));
        assertTrue(key.callIndex == 1);
    }
}
