// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { TestAtlas } from "../test/base/TestAtlas.sol";

import { SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "../src/contracts/atlas/Permit69.sol";
import { AtlasErrors } from "../src/contracts/types/AtlasErrors.sol";
import { ExecutionPhase } from "../src/contracts/types/LockTypes.sol";

contract Permit69Test is BaseTest {
    MockDAppControl mockDAppControl;
    address executionEnvironment;

    function setUp() public virtual override {
        BaseTest.setUp();

        mockDAppControl = new MockDAppControl();

        vm.startPrank(userEOA);
        executionEnvironment = atlas.createExecutionEnvironment({
            user: userEOA,
            control: address(mockDAppControl)
        });
        WETH.approve(address(atlas), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(mockDAppControl));
        WETH.approve(address(atlas), type(uint256).max);

        deal(WETH_ADDRESS, address(mockDAppControl), 100e18);
        deal(WETH_ADDRESS, userEOA, 100e18);
    }

    // transferUserERC20 tests

    function test_Permit69_TransferUserERC20RevertsIfCallerNotExecutionEnv() public {
        // Set active ExecutionEnvironment in Atlas
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));

        vm.prank(solverOneEOA); // Should revert because caller is not the ExecutionEnvironment
        vm.expectRevert(AtlasErrors.InvalidEnvironment.selector);
        atlas.transferUserERC20(WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(mockDAppControl));
    }

    function test_Permit69_TransferUserERC20RevertsIfEnvironmentMismatch() public {
        // Set active ExecutionEnvironment in Atlas
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));

        vm.prank(executionEnvironment); // Tries to transfer from GovEOA, not the user associated with EE
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        atlas.transferUserERC20(WETH_ADDRESS, solverOneEOA, 10e18, governanceEOA, address(mockDAppControl));
    }

    function test_Permit69_TransferUserERC20RevertsIfLockStateNotValid() public {
        // No User transfers allowed during AllocateValue phase
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.AllocateValue));

        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        atlas.transferUserERC20(WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(mockDAppControl));
    }

    function test_Permit69_TransferUserERC20SuccessfullyTransfersTokens() public {
        // Set active ExecutionEnvironment in Atlas
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));
        
        uint256 solverBalanceBefore = WETH.balanceOf(solverOneEOA);
        uint256 userBalanceBefore = WETH.balanceOf(userEOA);

        // Transfer tokens from user to solverOneEOA
        vm.prank(executionEnvironment);
        atlas.transferUserERC20(WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(mockDAppControl));

        // Check balances
        assertEq(WETH.balanceOf(solverOneEOA), solverBalanceBefore + 10e18, "Solver balance should increase by 10 WETH");
        assertEq(WETH.balanceOf(userEOA), userBalanceBefore - 10e18, "User balance should decrease by 10 WETH");
    }

    // transferDAppERC20 tests

    function test_Permit69_TransferDAppERC20RevertsIfCallerNotExecutionEnv() public {
        // Set active ExecutionEnvironment in Atlas
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));

        vm.prank(solverOneEOA); // Should revert because caller is not the ExecutionEnvironment
        vm.expectRevert(AtlasErrors.InvalidEnvironment.selector);
        atlas.transferDAppERC20(WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(mockDAppControl));
    }

    function test_Permit69_TransferDAppERC20RevertsIfEnvironmentMismatch() public {
        // Set active ExecutionEnvironment in Atlas
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));

        vm.prank(executionEnvironment); // Tries to transfer from GovEOA, not the user associated with EE
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        atlas.transferDAppERC20(WETH_ADDRESS, solverOneEOA, 10e18, governanceEOA, address(mockDAppControl));
    }

    function test_Permit69_TransferDAppERC20RevertsIfLockStateNotValid() public {
        // No DApp transfers allowed during UserOperation phase
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.UserOperation));

        vm.prank(executionEnvironment);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        atlas.transferDAppERC20(WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(mockDAppControl));
    }

    function test_Permit69_TransferDAppERC20SuccessfullyTransfersTokens() public {
        // Set active ExecutionEnvironment in Atlas
        atlas.setLock(executionEnvironment, 0, uint8(ExecutionPhase.PreOps));
        
        uint256 solverBalanceBefore = WETH.balanceOf(solverOneEOA);
        uint256 dAppControlBalanceBefore = WETH.balanceOf(address(mockDAppControl));

        // Transfer tokens from DAppControl to solverOneEOA
        vm.prank(executionEnvironment);
        atlas.transferDAppERC20(WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(mockDAppControl));

        // Check balances
        assertEq(WETH.balanceOf(solverOneEOA), solverBalanceBefore + 10e18, "Solver balance should increase by 10 WETH");
        assertEq(WETH.balanceOf(address(mockDAppControl)), dAppControlBalanceBefore - 10e18, "DAppControl balance should decrease by 10 WETH");
    }

    // constants tests
    function test_Permit69_ConstantValueOfSafeUserTransfer() public {
        uint8 SAFE_U = SAFE_USER_TRANSFER;

        // Safe phases for TransferUserERC20
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.PreOps)) != 0, "User transfer safe in PreOps");
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.UserOperation)) != 0, "User transfer safe in UserOperation");
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.PreSolver)) != 0, "User transfer safe in PreSolver");
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.PostSolver)) != 0, "User transfer safe in PostSolver");

        // Blocked phases for TransferUserERC20
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.Uninitialized)) == 0, "User transfer blocked in Uninitialized");
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.SolverOperation)) == 0, "User transfer blocked in SolverOperation");
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.AllocateValue)) == 0, "User transfer blocked in AllocateValue");
        assertTrue(SAFE_U & (1 << uint8(ExecutionPhase.FullyLocked)) == 0, "User transfer blocked in FullyLocked");
    }

    function test_Permit69_ConstantValueOfSafeDAppTransfer() public {
        uint8 SAFE_D = SAFE_DAPP_TRANSFER;

        // Safe phases for TransferDAppERC20
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.PreOps)) != 0, "DApp transfer safe in PreOps");
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.PreSolver)) != 0, "DApp transfer safe in PreSolver");
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.PostSolver)) != 0, "DApp transfer safe in PostSolver");
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.AllocateValue)) != 0, "DApp transfer safe in AllocateValue");

        // Blocked phases for TransferDAppERC20
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.Uninitialized)) == 0, "DApp transfer blocked in Uninitialized");
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.UserOperation)) == 0, "DApp transfer blocked in UserOperation");
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.SolverOperation)) == 0, "DApp transfer blocked in SolverOperation");
        assertTrue(SAFE_D & (1 << uint8(ExecutionPhase.FullyLocked)) == 0, "DApp transfer blocked in FullyLocked");
    }
}

contract MockDAppControl {
    // Just needs to return a uint32 when CALL_CONFIG() is called by Factory.sol
    function CALL_CONFIG() external pure returns (uint32) {
        return 0;
    }
}