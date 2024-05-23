//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/DAppApprovalTypes.sol";

library CallVerification {
    function getUserOperationHash(UserOperation memory userOp) internal pure returns (bytes32 userOpHash) {
        userOpHash = keccak256(abi.encode(userOp));
    }

    function getAltOperationHash(UserOperation memory userOp) internal pure returns (bytes32 altOpHash) {
        altOpHash = keccak256(
            abi.encodePacked(userOp.from, userOp.to, userOp.dapp, userOp.control, userOp.callConfig, userOp.sessionKey)
        );
    }

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

        if (dConfig.callConfig & 1 << uint32(CallConfigIndex.RequirePreOps) != 0) {
            // Start with preOps call if preOps is needed
            callSequence = abi.encodePacked(dConfig.to);
        }

        // Then user and solver call
        callSequence = abi.encodePacked(callSequence, abi.encode(userOp), abi.encode(solverOps));
        callSequenceHash = keccak256(callSequence);
    }
}
