//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/ConfigTypes.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";

library CallVerification {
    using CallBits for uint32;

    function getCallChainHash(
        DAppConfig memory dConfig,
        UserOperation memory userOp,
        SolverOperation[] memory solverOps
    )
        internal
        pure
        returns (bytes32 callSequenceHash)
    {
        bytes memory callSequence;

        if (dConfig.callConfig.needsPreOpsCall()) {
            // Start with preOps call if preOps is needed
            callSequence = abi.encodePacked(dConfig.to);
        }

        // Then user and solver call
        callSequence = abi.encodePacked(callSequence, abi.encode(userOp), abi.encode(solverOps));
        callSequenceHash = keccak256(callSequence);
    }
}
