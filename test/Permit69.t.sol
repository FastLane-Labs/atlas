// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import "./base/TestUtils.sol";

import { Permit69 } from "src/contracts/common/Permit69.sol";
import { Mimic } from "src/contracts/atlas/Mimic.sol";

import { SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "src/contracts/common/Permit69.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/LockTypes.sol";

contract Permit69Test is BaseTest {

    address mockExecutionEnvAddress = address(0x13371337);
    address mockDAppControl = address(0x123321);

    Context ctx;
    MockAtlasForPermit69Tests mockAtlas;

    function setUp() public virtual override {
        BaseTest.setUp();

        ctx = Context({
            executionEnvironment: address(0),
            userOpHash: bytes32(0),
            bundler: address(0),
            addressPointer: address(0),
            solverSuccessful: false,
            paymentsSuccessful: false,
            callIndex: 0,
            callCount: 0,
            phase: ExecutionPhase.PreOps,
            solverOutcome: 0,
            bidFind: false,
            isSimulation: false,
            callDepth: 0
        });

        mockAtlas = new MockAtlasForPermit69Tests(10, address(0), address(0), address(0));
        mockAtlas.setContext(ctx);
        mockAtlas.setEnvironment(mockExecutionEnvAddress);

        deal(WETH_ADDRESS, mockDAppControl, 100e18);
    }

    // transferUserERC20 tests

    function testTransferUserERC20RevertsIsCallerNotExecutionEnv() public {
        vm.prank(solverOneEOA);
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, address(0), uint8(0), uint8(ctx.phase)
        );
    }

    function testTransferUserERC20RevertsIfLockStateNotValid() public {
        // Check reverts at all invalid execution phases
        vm.startPrank(mockExecutionEnvAddress);

        // Uninitialized
        ctx.phase = (ExecutionPhase.Uninitialized);
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        // AllocateValue
        ctx.phase = (ExecutionPhase.AllocateValue);
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        // Releasing
        ctx.phase = (ExecutionPhase.Uninitialized);
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        vm.stopPrank();
    }

    function testTransferUserERC20SuccessfullyTransfersTokens() public {
        uint256 wethTransferred = 10e18;

        uint256 userWethBefore = WETH.balanceOf(userEOA);
        uint256 solverWethBefore = WETH.balanceOf(solverOneEOA);

        vm.prank(userEOA);
        WETH.approve(address(mockAtlas), wethTransferred);

        vm.prank(mockExecutionEnvAddress);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, wethTransferred, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        assertEq(WETH.balanceOf(userEOA), userWethBefore - wethTransferred, "User did not lose WETH");
        assertEq(WETH.balanceOf(solverOneEOA), solverWethBefore + wethTransferred, "Solver did not gain WETH");
    }

    // transferDAppERC20 tests

    function testTransferDAppERC20RevertsIsCallerNotExecutionEnv() public {
        vm.prank(solverOneEOA);
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );
    }

    function testTransferDAppERC20RevertsIfLockStateNotValid() public {
        // Check reverts at all invalid execution phases
        vm.startPrank(mockExecutionEnvAddress);

        // Uninitialized
        ctx.phase = ExecutionPhase.Uninitialized;
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        // UserOperation
        ctx.phase = (ExecutionPhase.UserOperation);
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        // SolverOperations
        ctx.phase = (ExecutionPhase.SolverOperations);
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        // Releasing
        ctx.phase = (ExecutionPhase.Uninitialized);
        mockAtlas.setContext(ctx);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        vm.stopPrank();
    }

    function testTransferDAppERC20SuccessfullyTransfersTokens() public {
        uint256 wethTransferred = 10e18;

        uint256 dAppWethBefore = WETH.balanceOf(mockDAppControl);
        uint256 solverWethBefore = WETH.balanceOf(solverOneEOA);

        vm.prank(mockDAppControl);
        WETH.approve(address(mockAtlas), wethTransferred);

        vm.prank(mockExecutionEnvAddress);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, wethTransferred, userEOA, mockDAppControl, uint8(0), uint8(ctx.phase)
        );

        assertEq(WETH.balanceOf(mockDAppControl), dAppWethBefore - wethTransferred, "DApp did not lose WETH");
        assertEq(WETH.balanceOf(solverOneEOA), solverWethBefore + wethTransferred, "Solver did not gain WETH");
    }

    // constants tests
    function testConstantValueOfSafeUserTransfer() public {
        string memory expectedBitMapString = "0000101011100000";
        // Safe phases for user transfers are PreOps, UserOperation, and DAppOperation
        // preOpsPhaseSafe = 0000 0000 0010 0000
        uint8 preOpsPhaseSafe = uint8(ExecutionPhase.PreOps);
        // userOpPhaseSafe = 0000 0000 0100 0000
        uint8 userOpPhaseSafe = uint8(ExecutionPhase.UserOperation);

        uint8 preSolverOpsPhaseSafe = uint8(ExecutionPhase.PreSolver);
        uint8 postSolverOpsPhaseSafe = uint8(ExecutionPhase.PostSolver);
        // verificationPhaseSafe = 0000 0100 0000 0000
        uint8 verificationPhaseSafe = uint8(ExecutionPhase.PostOps);

        uint8 expectedSafeUserTransferBitMap =
            preOpsPhaseSafe | userOpPhaseSafe | preSolverOpsPhaseSafe | postSolverOpsPhaseSafe | verificationPhaseSafe;

        assertEq(
            mockAtlas.getSafeUserTransfer(),
            expectedSafeUserTransferBitMap,
            "Expected to be the bitwise OR of the safe phases (0000 0100 1110 0000)"
        );
        assertEq(
            TestUtils.uint16ToBinaryString(expectedSafeUserTransferBitMap),
            expectedBitMapString,
            "Binary string form of bit map not as expected"
        );
    }

    function testConstantValueOfSafeDAppTransfer() public {
        string memory expectedBitMapString = "0000111010100000";
        // Safe phases for dApp transfers are PreOps, AllocateValue, and DAppOperation
        // preOpsPhaseSafe = 0000 0000 0010 0000
        uint8 preOpsPhaseSafe = uint8(ExecutionPhase.PreOps);
        // userOpPhaseSafe = 0000 0000 0100 0000
        uint8 userOpPhaseSafe = uint8(ExecutionPhase.UserOperation);

        uint8 preSolverOpsPhaseSafe = uint8(ExecutionPhase.PreSolver);
        uint8 postSolverOpsPhaseSafe = uint8(ExecutionPhase.PostSolver);
        uint8 allocateValuePhaseSafe = uint8(ExecutionPhase.AllocateValue);
        // verificationPhaseSafe = 0000 0100 0000 0000
        uint8 verificationPhaseSafe = uint8(ExecutionPhase.PostOps);

        uint16 expectedSafeDAppTransferBitMap =
            preOpsPhaseSafe | preSolverOpsPhaseSafe | postSolverOpsPhaseSafe | allocateValuePhaseSafe | verificationPhaseSafe;

        assertEq(
            mockAtlas.getSafeDAppTransfer(),
            expectedSafeDAppTransferBitMap,
            "Expected to be the bitwise OR of the safe phases (0000 0111 0010 0000)"
        );
        assertEq(
            TestUtils.uint16ToBinaryString(expectedSafeDAppTransferBitMap),
            expectedBitMapString,
            "Binary string form of bit map not as expected"
        );
    }

    function testVerifyCallerIsExecutionEnv() public {
        vm.prank(solverOneEOA);
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        mockAtlas.verifyCallerIsExecutionEnv(solverOneEOA, userEOA, 0);

        vm.prank(mockExecutionEnvAddress);
        bool res = mockAtlas.verifyCallerIsExecutionEnv(solverOneEOA, userEOA, 0);
        assertTrue(res, "Should return true and not revert");
    }
}

// Mock Atlas with standard implementations of Permit69's virtual functions
contract MockAtlasForPermit69Tests is Permit69 {
    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        Permit69(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    // Declared in SafetyLocks.sol in the canonical Atlas system
    // The only property relevant to testing Permit69 is _ctx.phase (bitwise uint16)
    Context internal _ctx;
    address internal _environment;

    function getSafeUserTransfer() public pure returns (uint16) {
        return SAFE_USER_TRANSFER;
    }

    function getSafeDAppTransfer() public pure returns (uint16) {
        return SAFE_DAPP_TRANSFER;
    }

    // Setters for testing
    function setContext(Context memory ctx) public {
        _ctx = ctx;
    }

    function setEnvironment(address _activeEnvironment) public {
        _environment = _activeEnvironment;
    }

    // Overriding the virtual functions in Permit69
    function _verifyCallerIsExecutionEnv(address, address, uint32) internal view override {
        if (msg.sender != _environment) {
            revert AtlasErrors.EnvironmentMismatch();
        }
    }

    // Exposing above overridden function for testing and Permit69 coverage
    function verifyCallerIsExecutionEnv(address user, address control, uint32 callConfig) public view returns (bool) {
        _verifyCallerIsExecutionEnv(user, control, callConfig);
        return true; // Added to test lack of revert
    }

    // Implemented in Factory.sol in the canonical Atlas system
    function _getLockState() internal view virtual returns (Context memory) {
        return _ctx;
    }
}
