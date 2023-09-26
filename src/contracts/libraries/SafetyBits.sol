//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/LockTypes.sol";

uint16 constant EXECUTION_PHASE_OFFSET = uint16(type(BaseLock).max) + 1;
uint16 constant SAFETY_LEVEL_OFFSET = uint16(type(BaseLock).max) + uint16(type(ExecutionPhase).max) + 2;

library SafetyBits {

    uint16 internal constant _LOCKED_X_SOLVERS_X_REQUESTED = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Requested))
    );

    uint16 internal constant _LOCKED_X_SOLVERS_X_VERIFIED = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Verified))
    );

    uint16 internal constant _ACTIVE_X_PRE_OPS_X_UNSET = uint16(
        1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _PENDING_X_RELEASING_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.Releasing))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_PRE_OPS_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreOps))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_USER_X_UNSET = uint16(
        1 << uint16(BaseLock.Active) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_USER_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserOperation))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _PENDING_X_SOLVER_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_SOLVER_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _LOCK_PAYMENTS = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.HandlingPayments))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _NO_SOLVER_SUCCESS = uint16(
        1 << uint16(BaseLock.Active) | 
        1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps)) |
        1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _ACTIVE_X_REFUND_X_UNSET = uint16(
        1 << uint16(BaseLock.Pending) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.UserRefund))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    uint16 internal constant _LOCKED_X_VERIFICATION_X_UNSET = uint16(
        1 << uint16(BaseLock.Locked) | 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PostOps))
            | 1 << (SAFETY_LEVEL_OFFSET + uint16(SolverSafety.Unset))
    );

    function pack(EscrowKey memory self)
        internal
        pure
        returns (bytes32 packedKey)
    {
        packedKey = bytes32(
            abi.encodePacked(
                self.approvedCaller,
                self.makingPayments,
                self.paymentsComplete,
                self.callIndex,
                self.callMax,
                self.lockState,
                self.gasRefund,
                self.isSimulation,
                uint8(0) // callDepth
            )
        );
    }

    function holdDAppOperationLock(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _LOCKED_X_VERIFICATION_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function setAllSolversFailed(EscrowKey memory self)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.lockState = _NO_SOLVER_SUCCESS;
        self.approvedCaller = address(0);
        self.callIndex = self.callMax - 1;
        return self;
    }

    function allocationComplete(EscrowKey memory self) internal pure returns (EscrowKey memory) {
        self.makingPayments = false;
        self.paymentsComplete = true;
        return self;
    }

    function turnSolverLockPayments(EscrowKey memory self, address approvedCaller)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.makingPayments = true;
        self.lockState = _LOCK_PAYMENTS;
        self.approvedCaller = approvedCaller;
        return self;
    }

    function holdSolverLock(EscrowKey memory self, address nextSolver) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SOLVERS_X_REQUESTED;
        self.approvedCaller = nextSolver;
        return self;
    }

    function holdUserLock(EscrowKey memory self, address approvedCaller) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_USER_X_UNSET;
        self.approvedCaller = approvedCaller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function holdPreOpsLock(EscrowKey memory self, address controller) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_PRE_OPS_X_UNSET;
        self.approvedCaller = controller;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function initializeEscrowLock(EscrowKey memory self, bool needsPreOps, uint8 solverOpCount, address nextCaller, bool isSimulation)
        internal
        pure
        returns (EscrowKey memory)
    {
        self.approvedCaller = nextCaller;
        self.callMax = solverOpCount + 3;
        self.callIndex = needsPreOps ? 0 : 1;
        self.lockState = needsPreOps ? _ACTIVE_X_PRE_OPS_X_UNSET : _ACTIVE_X_USER_X_UNSET;
        self.isSimulation = isSimulation;
        return self;
    }

    function turnSolverLock(EscrowKey memory self, address msgSender) internal pure returns (EscrowKey memory) {
        self.lockState = _LOCKED_X_SOLVERS_X_VERIFIED;
        self.approvedCaller = msgSender;
        return self;
    }
}
