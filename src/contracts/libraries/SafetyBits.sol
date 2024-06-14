//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/LockTypes.sol";

// NOTE: No user transfers allowed during AllocateValue
uint8 constant SAFE_USER_TRANSFER = uint8(
    1 << (uint8(ExecutionPhase.PreOps)) | 1 << (uint8(ExecutionPhase.UserOperation))
        | 1 << (uint8(ExecutionPhase.PreSolver)) | 1 << (uint8(ExecutionPhase.PostSolver))
        | 1 << (uint8(ExecutionPhase.PostOps))
);

// NOTE: No Dapp transfers allowed during UserOperation
uint8 constant SAFE_DAPP_TRANSFER = uint8(
    1 << (uint8(ExecutionPhase.PreOps)) | 1 << (uint8(ExecutionPhase.PreSolver))
        | 1 << (uint8(ExecutionPhase.PostSolver)) | 1 << (uint8(ExecutionPhase.AllocateValue))
        | 1 << (uint8(ExecutionPhase.PostOps))
);

library SafetyBits {
    function setAndPack(
        Context memory self,
        ExecutionPhase phase,
        bool increment
    )
        internal
        pure
        returns (bytes memory packedKey)
    {
        if (increment) {
            unchecked {
                ++self.callIndex;
            }
        }
        packedKey = abi.encodePacked(
            self.bundler,
            self.solverSuccessful,
            self.paymentsSuccessful,
            self.callIndex,
            self.callCount,
            uint8(phase),
            uint8(0),
            self.solverOutcome,
            self.bidFind,
            self.isSimulation,
            uint8(1) // callDepth
        );
    }
}
