// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";
import "src/contracts/types/LockTypes.sol";
import "../base/TestUtils.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";

import { CallConfigIndex } from "src/contracts/types/DAppApprovalTypes.sol";

contract SafetyBitsTest is Test {
    using SafetyBits for Context;
    using CallBits for uint32;

    function initializeContext(CallConfigIndex index) public view returns (Context memory ctx) {
        uint32 callConfig = uint32(1 << uint256(index));
        ctx = _buildContext(callConfig, address(0), bytes32(0), address(0), 1, false);
    }

    function _getCallConfig(CallConfigIndex index) internal pure returns (uint32 callConfig) {
        callConfig = uint32(1 << uint256(index));
    }

    function _buildContext(
        uint32 callConfig,
        address executionEnvironment,
        bytes32 userOpHash,
        address bundler,
        uint8 solverOpCount,
        bool isSimulation
    )
        internal
        view
        returns (Context memory)
    {   
        return Context({
            executionEnvironment: executionEnvironment,
            userOpHash: userOpHash,
            bundler: bundler,
            addressPointer: executionEnvironment,
            solverSuccessful: false,
            paymentsSuccessful: false,
            callIndex: callConfig.needsPreOpsCall() ? 0 : 1,
            callCount: solverOpCount + 3,
            phase: ExecutionPhase.Uninitialized,
            solverOutcome: 0,
            bidFind: false,
            isSimulation: isSimulation,
            callDepth: 0
        });
    }

    function testInitializeEscrowLock() public {
        Context memory ctx = initializeContext(CallConfigIndex.RequirePreOps);
        assertTrue(ctx.addressPointer == address(0));
        assertTrue(ctx.solverSuccessful == false);
        assertTrue(ctx.paymentsSuccessful == false);
        assertTrue(ctx.callIndex == 0);
        assertTrue(ctx.callCount == 4);
        assertTrue(ctx.phase == ExecutionPhase.Uninitialized);
        assertTrue(ctx.solverOutcome == 0);
    }

    function testPack() public {
        Context memory ctx = initializeContext(CallConfigIndex.RequirePostOpsCall);
        ctx = ctx.setUserPhase(address(1));
        bytes32 want = 0x0000000000000000000000000000000000000001000002040048000000000001;
        bytes32 packed = bytes32(ctx.pack());
        // console.logBytes32(want);
        // console.logBytes32(packed);
        assertTrue(packed == want);
    }

    function testHoldDAppOperationLock() public {
        Context memory ctx = initializeContext(CallConfigIndex.RequirePostOpsCall);
        ctx.addressPointer = address(1);
        ctx.callCount = 4;
        ctx.callIndex = 2;
        ctx = ctx.setPostOpsPhase();
        assertTrue(ctx.phase == ExecutionPhase.PostOps);
        assertFalse(ctx.addressPointer == address(1));
        assertTrue(ctx.callIndex == 3);

        Context memory newCtx = initializeContext(CallConfigIndex.RequirePostOpsCall);
        newCtx.addressPointer = address(1);
        newCtx.solverSuccessful = true;
        newCtx.callCount = 4;
        newCtx.callIndex = 2;
        newCtx = newCtx.setPostOpsPhase();
        assertTrue(newCtx.addressPointer == address(1));
        assertTrue(newCtx.callIndex == 3);
    }

    function testTurnSolverLockPayments() public {
        Context memory ctx = initializeContext(CallConfigIndex.RequireFulfillment);
        ctx = ctx.setAllocateValuePhase(address(1));
        assertTrue(ctx.phase == ExecutionPhase.AllocateValue);
        assertTrue(ctx.addressPointer == address(1));
    }

    function testHoldUserLock() public {
        Context memory ctx = initializeContext(CallConfigIndex.RequirePreOps);
        ctx = ctx.setUserPhase(address(1));
        assertTrue(ctx.phase == ExecutionPhase.UserOperation);
        assertTrue(ctx.addressPointer == address(1));
        assertTrue(ctx.callIndex == 1);
    }

    function testHoldPreOpsLock() public {
        Context memory ctx = initializeContext(CallConfigIndex.RequirePreOps);
        ctx = ctx.setPreOpsPhase(address(1));
        assertTrue(ctx.phase == ExecutionPhase.PreOps);
        assertTrue(ctx.addressPointer == address(1));
        assertTrue(ctx.callIndex == 1);
    }
}
