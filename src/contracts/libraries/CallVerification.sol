//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "src/contracts/interfaces/IDAppControl.sol";

import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/DAppApprovalTypes.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";

library CallVerification {
    using CallBits for uint32;

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
        uint256 i;
        if (dConfig.callConfig.needsPreOpsCall()) {
            // Start with preOps call if preOps is needed
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // initial hash = null
                    dConfig.to,
                    abi.encodeCall(IDAppControl.preOpsCall, userOp),
                    i++
                )
            );
        }

        // then user call
        callSequenceHash = keccak256(
            abi.encodePacked(
                callSequenceHash, // always reference previous hash
                abi.encode(userOp),
                i++
            )
        );

        // then solver calls
        uint256 count = solverOps.length;
        for (uint256 n; n < count; ++n) {
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // reference previous hash
                    abi.encode(solverOps[n]), // solver op
                    i++
                )
            );
        }
    }
}
