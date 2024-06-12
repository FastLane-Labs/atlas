//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/LockTypes.sol";

// TODO remove
//import {TestUtils} from "../../../test/base/TestUtils.sol";
// import "forge-std/Test.sol";

// uint16 bit layout:  BBBB BBBB AAAA
// Where A = BaseLock, B = ExecutionPhase,

uint16 constant EXECUTION_PHASE_OFFSET = uint16(type(BaseLock).max) + 1;

// NOTE: No user transfers allowed during HandlingPayments
uint16 constant SAFE_USER_TRANSFER = 0x0ae0; // 2784
    /* 
        uint16( 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreSolver))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostSolver))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps))
        */

// NOTE: No Dapp transfers allowed during UserOperation
uint16 constant SAFE_DAPP_TRANSFER = 0x0ca0; // 3232
    /*
        uint16(1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreSolver))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
            | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps))
        */

library SafetyBits {

    uint16 internal constant _LOCKED_X_PRESOLVERS_X_REQUESTED = // 
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET +
        uint16(ExecutionPhase.PreSolver)));

    uint16 internal constant _LOCKED_X_POSTSOLVERS_X_REQUESTED = // 
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET +
        uint16(ExecutionPhase.PostSolver)));

    uint16 internal constant _LOCKED_X_SOLVERS_X_REQUESTED = 0x0108; // 264
        // uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET +
        // uint16(ExecutionPhase.SolverOperations)));

    uint16 internal constant _LOCKED_X_PRE_OPS_X_UNSET = 0x0028; // 40
        // uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps)));

    uint16 internal constant _LOCKED_X_USER_X_UNSET = 0x0048; // 72
        // uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation)));

    uint16 internal constant _LOCK_PAYMENTS = 0x0408; // 1032
        // uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET +
        // uint16(ExecutionPhase.HandlingPayments)));

    uint16 internal constant _LOCKED_X_VERIFICATION_X_UNSET = 0x0808; // 2056
        // uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps)));

    function pack(EscrowKey memory self) internal pure returns (bytes memory packedKey) {
        packedKey = abi.encodePacked(
            self.addressPointer,
            self.solverSuccessful,
            self.paymentsSuccessful,
            self.callIndex,
            self.callCount,
            self.lockState,
            self.solverOutcome,
            self.bidFind,
            self.isSimulation,
            uint8(1) // callDepth
        );
    }

    function holdPreOpsLock(EscrowKey memory self, address control) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_PRE_OPS_X_UNSET;
        self.addressPointer = control;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function holdUserLock(EscrowKey memory self, address addressPointer) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_USER_X_UNSET;
        self.addressPointer = addressPointer;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function holdPreSolverLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_PRESOLVERS_X_REQUESTED;
        self.addressPointer = self.executionEnvironment;
        return self;
    }

    function holdPostSolverLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_POSTSOLVERS_X_REQUESTED;
        self.addressPointer = self.executionEnvironment;
        return self;
    }

    function holdSolverLock(EscrowKey memory self, address nextSolver) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SOLVERS_X_REQUESTED;
        self.addressPointer = nextSolver;
        return self;
    }

    function holdAllocateValueLock(
        EscrowKey memory self,
        address addressPointer
    )
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _LOCK_PAYMENTS;
        self.addressPointer = addressPointer;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function holdPostOpsLock(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        if (!self.solverSuccessful) {
            self.addressPointer = address(0); // TODO: Point this to bundler (or builder?) if all solvers fail
        }
        self.lockState = _LOCKED_X_VERIFICATION_X_UNSET;
        self.callIndex = self.callCount - 1;
        return self;
    }
}
