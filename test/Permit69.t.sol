// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";


import {Permit69} from "src/contracts/atlas/Permit69.sol";
import "src/contracts/types/LockTypes.sol";



contract Permit69Test is BaseTest {

    MockAtlasForPermit69Tests mockAtlas;

    function setUp() public virtual override {
        BaseTest.setUp();

        mockAtlas = new MockAtlasForPermit69Tests();
    }

    // transferUserERC20 tests

    function testTransferUserERC20RevertsIfCallerNotExecutionEnv() public {}

    function testTransferUserERC20RevertsIfLockStateNotValid() public {
        // Check reverts at all invalid execution phases
    }

    function testTransferUserERC20SuccessfullyTransfersTokens() public {}

    // transferProtocolERC20 tests

    function testTransferProtocolERC20RevertsIfCallerNotExecutionEnv() public {}

    function testTransferProtocolERC20RevertsIfLockStateNotValid() public {
        // Check reverts at all invalid execution phases
    }

    function testTransferProtocolERC20SuccessfullyTransfersTokens() public {}

    // constants tests

    function testConstantValueOfExecutionPhaseOffset() public {
        // Offset skips BaseLock bits to get to ExecutionPhase bits
        // i.e. 4 right-most bits of skipped for BaseLock (xxxx xxxx xxxx 0000)
        assertEq(
            mockAtlas.getExecutionPhaseOffset(),
            uint16(type(BaseLock).max),
            'Offset not same as num of items in BaseLock enum'
        );
        assertEq(
            uint16(type(BaseLock).max),
            uint16(3),
            'Expected 4 items in BaseLock enum'
        );
    }

    function testConstantValueOfSafeUserTransfer() public {
        // Safe phases for user transfers are Staging, UserCall, and Verification
        // stagePhaseSafe = 0000 0000 0010 0000
        uint16 stagePhaseSafe = uint16(
            1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.Staging))
        );
        // userCallPhaseSafe = 0000 0000 0100 0000
        uint16 userCallPhaseSafe = uint16(
            1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.UserCall))
        );
        // verificationPhaseSafe = 0000 0100 0000 0000
        uint16 verificationPhaseSafe = uint16(
            1 << (mockAtlas.getExecutionPhaseOffset() + uint16(ExecutionPhase.Verification))
        );

        uint16 expectedSafeUserTransferBitMap = 
                stagePhaseSafe
            |   userCallPhaseSafe
            |   verificationPhaseSafe;
        
        assertEq(
            mockAtlas.getSafeUserTransfer(),
            expectedSafeUserTransferBitMap,
            'Expected to be the bitwise OR of the safe phases (0000 0100 0110 0000)'
        );
    }

    function testConstantValueOfSafeProtocolTransfer() public {}


}

// TODO probably refactor some of this stuff to a shared folder of standard implementations
// Mock Atlas with standard implementations of Permit69's virtual functions
contract MockAtlasForPermit69Tests is Permit69 {

    // Declared in SafetyLocks.sol in the canonical Atlas system
    // The only property relevant to testing Permit69 is _escrowKey.lockState (bitwise uint16)
    EscrowKey internal _escrowKey;

    // Public functions to expose the internal constants for testing
    function getExecutionPhaseOffset() public view returns (uint16) {
        return _EXECUTION_PHASE_OFFSET;
    }

    function getSafeUserTransfer() public view returns (uint16) {
        return _SAFE_USER_TRANSFER;
    }

    function getSafeProtocolTransfer() public view returns (uint16) {
        return _SAFE_PROTOCOL_TRANSFER;
    }

    // Setters for testing
    function setEscrowKey(EscrowKey memory escrowKey) public {
        _escrowKey = escrowKey;
    }

    // Overriding the virtual functions in Permit69
    function _getExecutionEnvironmentCustom(
        address user,
        bytes32 controlCodeHash,
        address protocolControl,
        uint16 callConfig
    ) internal view virtual override returns (address environment) {}

    // Implemented in Factory.sol in the canonical Atlas system
    function _getLockState()
        internal
        view
        virtual
        override
        returns (EscrowKey memory)
    {
        return _escrowKey;
    }
}