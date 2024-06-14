//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/LockTypes.sol";

// NOTE: No user transfers allowed during AllocateValue
uint8 constant SAFE_USER_TRANSFER = uint8(
    1 << (uint8(ExecutionPhase.PreOps))
        | 1 << (uint8(ExecutionPhase.UserOperation))
        | 1 << (uint8(ExecutionPhase.PreSolver))
        | 1 << (uint8(ExecutionPhase.PostSolver))
        | 1 << (uint8(ExecutionPhase.PostOps))
);

// NOTE: No Dapp transfers allowed during UserOperation
uint8 constant SAFE_DAPP_TRANSFER = uint8(
    1 << (uint8(ExecutionPhase.PreOps))
        | 1 << (uint8(ExecutionPhase.PreSolver))
        | 1 << (uint8(ExecutionPhase.PostSolver))
        | 1 << (uint8(ExecutionPhase.AllocateValue))
        | 1 << (uint8(ExecutionPhase.PostOps))
);

library SafetyBits {
    function pack(Context memory self) internal pure returns (bytes memory packedKey) {
        packedKey = abi.encodePacked(
            self.addressPointer,
            self.solverSuccessful,
            self.paymentsSuccessful,
            self.callIndex,
            self.callCount,
            uint8(self.phase),
            uint8(0),
            self.solverOutcome,
            self.bidFind,
            self.isSimulation,
            uint8(1) // callDepth
        );
    }

    function setPreOpsPhase(Context memory self, address control) internal pure returns (Context memory) {
        self.phase = ExecutionPhase.PreOps;
        self.addressPointer = control;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function setUserPhase(Context memory self, address userOpDapp) internal pure returns (Context memory) {
        self.phase = ExecutionPhase.UserOperation;
        self.addressPointer = userOpDapp;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function setPreSolverPhase(Context memory self) internal pure returns (Context memory) {
        self.phase = ExecutionPhase.PreSolver;
        self.addressPointer = self.executionEnvironment;
        return self;
    }

    function setPostSolverPhase(Context memory self) internal pure returns (Context memory) {
        self.phase = ExecutionPhase.PostSolver;
        self.addressPointer = self.executionEnvironment;
        return self;
    }

    function setAllocateValuePhase(
        Context memory self,
        address addressPointer
    )
        internal
        pure
        returns (Context memory)
    {
        self.phase = ExecutionPhase.AllocateValue;
        self.addressPointer = addressPointer;
        unchecked {
            ++self.callIndex;
        }
        return self;
    }

    function setPostOpsPhase(Context memory self) internal pure returns (Context memory) {
        if (!self.solverSuccessful) {
            self.addressPointer = address(0); // TODO: Point this to bundler (or builder?) if all solvers fail
        }
        self.phase = ExecutionPhase.PostOps;
        self.callIndex = self.callCount - 1;
        return self;
    }
}
