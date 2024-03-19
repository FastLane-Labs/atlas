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
uint16 constant SAFE_USER_TRANSFER = uint16(
    1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreSolver))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostSolver))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps))
);

// NOTE: No Dapp transfers allowed during UserOperation
uint16 constant SAFE_DAPP_TRANSFER = uint16(
    1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreSolver))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
        | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps))
);

library SafetyBits {
    uint16 internal constant _LOCKED_X_SOLVERS_X_REQUESTED =
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations)));

    uint16 internal constant _ACTIVE_X_PRE_OPS_X_UNSET =
        uint16(1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps)));

    uint16 internal constant _LOCKED_X_PRE_OPS_X_UNSET =
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps)));

    uint16 internal constant _ACTIVE_X_USER_X_UNSET =
        uint16(1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation)));

    uint16 internal constant _LOCKED_X_USER_X_UNSET =
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation)));

    uint16 internal constant _LOCK_PAYMENTS =
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments)));

    uint16 internal constant _LOCKED_X_VERIFICATION_X_UNSET =
        uint16(1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps)));

    function pack(EscrowKey memory self) internal pure returns (bytes32 packedKey) {
        packedKey = bytes32(
            abi.encodePacked(
                self.addressPointer,
                self.solverSuccessful,
                self.paymentsSuccessful,
                self.callIndex,
                self.callCount,
                self.lockState,
                self.blank,
                self.bidFind,
                self.isSimulation,
                uint8(1) // callDepth
            )
        );
    }

    function initializeEscrowLock(
        EscrowKey memory self,
        bytes32 userOpHash,
        address bundler,
        bool needsPreOps,
        uint8 solverOpCount,
        address executionEnvironment,
        bool isSimulation
    )
        internal
        pure
        returns (EscrowKey memory)
    {
        self.executionEnvironment = executionEnvironment;
        self.userOpHash = userOpHash;
        self.bundler = bundler;
        self.addressPointer = executionEnvironment;
        self.callCount = solverOpCount + 3;
        self.callIndex = needsPreOps ? 0 : 1;
        self.lockState = needsPreOps ? _ACTIVE_X_PRE_OPS_X_UNSET : _ACTIVE_X_USER_X_UNSET;
        self.isSimulation = isSimulation;
        self.bidFind = false;
        return self;
    }

    function holdPreOpsLock(EscrowKey memory self, address controller) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_PRE_OPS_X_UNSET;
        self.addressPointer = controller;
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

    function holdSolverLock(EscrowKey memory self, address nextSolver) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SOLVERS_X_REQUESTED;
        self.addressPointer = nextSolver;
        unchecked {
            ++self.callIndex;
        }
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
