//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/ConfigTypes.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";

library CallVerification {
    using CallBits for uint32;

    function getCallChainHash(
        UserOperation memory userOp,
        SolverOperation[] memory solverOps
    )
        internal
        pure
        returns (bytes32 callSequenceHash)
    {
        bytes memory callSequence = abi.encodePacked(abi.encode(userOp), abi.encode(solverOps));
        callSequenceHash = keccak256(callSequence);
    }
}
