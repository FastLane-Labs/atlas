// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import "./base/TestUtils.sol";

import { Permit69 } from "src/contracts/common/Permit69.sol";
import { Mimic } from "src/contracts/atlas/Mimic.sol";

import { EXECUTION_PHASE_OFFSET } from "src/contracts/libraries/SafetyBits.sol";
import { SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "src/contracts/common/Permit69.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/LockTypes.sol";

contract Permit69Test is BaseTest {
    uint16 constant EXEC_PHASE_PRE_OPS = uint16(1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps)));

    address mockExecutionEnvAddress = address(0x13371337);
    address mockDAppControl = address(0x123321);

    EscrowKey escrowKey;
    MockAtlasForPermit69Tests mockAtlas;

    function setUp() public virtual override {
        BaseTest.setUp();

        escrowKey = EscrowKey({
            executionEnvironment: address(0),
            userOpHash: bytes32(0),
            bundler: address(0),
            addressPointer: address(0),
            solverSuccessful: false,
            paymentsSuccessful: false,
            callIndex: 0,
            callCount: 0,
            lockState: EXEC_PHASE_PRE_OPS,
            solverOutcome: 0,
            bidFind: false,
            isSimulation: false,
            callDepth: 0
        });

        mockAtlas = new MockAtlasForPermit69Tests(10, address(0), address(0), address(0));
        mockAtlas.setEscrowKey(escrowKey);
        mockAtlas.setEnvironment(mockExecutionEnvAddress);

        deal(WETH_ADDRESS, mockDAppControl, 100e18);
    }

    // transferUserERC20 tests

    function testTransferUserERC20RevertsIsCallerNotExecutionEnv() public {
        vm.prank(solverOneEOA);
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );
    }

    function testTransferUserERC20RevertsIfLockStateNotValid() public {
        // Check reverts at all invalid execution phases
        vm.startPrank(mockExecutionEnvAddress);

        // Uninitialized
        escrowKey.lockState = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.Uninitialized)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );

        // HandlingPayments
        escrowKey.lockState =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.HandlingPayments)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );

        // Releasing
        escrowKey.lockState = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.Releasing)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferUserERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
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
            WETH_ADDRESS, solverOneEOA, wethTransferred, escrowKey.lockState
        );

        assertEq(WETH.balanceOf(userEOA), userWethBefore - wethTransferred, "User did not lose WETH");
        assertEq(WETH.balanceOf(solverOneEOA), solverWethBefore + wethTransferred, "Solver did not gain WETH");
    }

    // transferDAppERC20 tests

    function testTransferDAppERC20RevertsIsCallerNotExecutionEnv() public {
        vm.prank(solverOneEOA);
        vm.expectRevert(AtlasErrors.EnvironmentMismatch.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );
    }

    function testTransferDAppERC20RevertsIfLockStateNotValid() public {
        // Check reverts at all invalid execution phases
        vm.startPrank(mockExecutionEnvAddress);

        // Uninitialized
        escrowKey.lockState = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.Uninitialized)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );

        // UserOperation
        escrowKey.lockState = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.UserOperation)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );

        // SolverOperations
        escrowKey.lockState =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.SolverOperations)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
        );

        // Releasing
        escrowKey.lockState = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.Releasing)));
        mockAtlas.setEscrowKey(escrowKey);
        vm.expectRevert(AtlasErrors.InvalidLockState.selector);
        mockAtlas.transferDAppERC20(
            WETH_ADDRESS, solverOneEOA, 10e18, escrowKey.lockState
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
            WETH_ADDRESS, solverOneEOA, wethTransferred, escrowKey.lockState
        );

        assertEq(WETH.balanceOf(mockDAppControl), dAppWethBefore - wethTransferred, "DApp did not lose WETH");
        assertEq(WETH.balanceOf(solverOneEOA), solverWethBefore + wethTransferred, "Solver did not gain WETH");
    }

    // constants tests

    function testConstantValueOfExecutionPhaseOffset() public {
        // Offset skips BaseLock bits to get to ExecutionPhase bits
        // i.e. 4 right-most bits of skipped for BaseLock (xxxx xxxx xxxx 0000)
        // NOTE: An extra skip is added to account for ExecutionPhase values starting at 0
        assertEq(
            mockAtlas.getExecutionPhaseOffset(),
            uint16(type(BaseLock).max) + 1,
            "Offset not same as num of items in BaseLock enum"
        );
        assertEq(uint16(type(BaseLock).max), uint16(3), "Expected 4 items in BaseLock enum");
    }

    function testConstantValueOfSafeUserTransfer() public {
        string memory expectedBitMapString = "0000101011100000";
        // Safe phases for user transfers are PreOps, UserOperation, and DAppOperation
        // preOpsPhaseSafe = 0000 0000 0010 0000
        uint16 preOpsPhaseSafe = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PreOps)));
        // userOpPhaseSafe = 0000 0000 0100 0000
        uint16 userOpPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.UserOperation)));

        uint16 preSolverOpsPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PreSolver)));
        uint16 postSolverOpsPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PostSolver)));
        // verificationPhaseSafe = 0000 0100 0000 0000
        uint16 verificationPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PostOps)));

        uint16 expectedSafeUserTransferBitMap =
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
        string memory expectedBitMapString = "0000110010100000";
        // Safe phases for dApp transfers are PreOps, HandlingPayments, and DAppOperation
        // preOpsPhaseSafe = 0000 0000 0010 0000
        uint16 preOpsPhaseSafe = uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PreOps)));
        // handlingPaymentsPhaseSafe = 0000 0001 0000 0000
        uint16 handlingPaymentsPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.HandlingPayments)));

        uint16 preSolverPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PreSolver)));

        // verificationPhaseSafe = 0000 0100 0000 0000
        uint16 verificationPhaseSafe =
            uint16(1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.PostOps)));

        uint16 expectedSafeDAppTransferBitMap =
            preOpsPhaseSafe | preSolverPhaseSafe | handlingPaymentsPhaseSafe | verificationPhaseSafe;

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
    // The only property relevant to testing Permit69 is _escrowKey.lockState (bitwise uint16)
    EscrowKey internal _escrowKey;
    address internal _environment;

    // Public functions to expose the internal constants for testing
    function getExecutionPhaseOffset() public pure returns (uint16) {
        return EXECUTION_PHASE_OFFSET;
    }

    function getSafeUserTransfer() public pure returns (uint16) {
        return SAFE_USER_TRANSFER;
    }

    function getSafeDAppTransfer() public pure returns (uint16) {
        return SAFE_DAPP_TRANSFER;
    }

    // Setters for testing
    function setEscrowKey(EscrowKey memory escrowKey) public {
        _escrowKey = escrowKey;
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
    function _getLockState() internal view virtual returns (EscrowKey memory) {
        return _escrowKey;
    }
}
