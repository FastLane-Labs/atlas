//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/DAppApprovalTypes.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";

bytes32 constant USER_TYPEHASH_DEFAULT = keccak256(
    "UserOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address dapp,address control,uint32 callConfig,address sessionKey,bytes data)"
);

bytes32 constant USER_TYPEHASH_TRUSTED = keccak256(
    "UserOperation(address from,address to,address dapp,address control,uint32 callConfig,address sessionKey)"
);

bytes32 constant USER_TYPEHASH_FULL = keccak256(
    "UserOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address dapp,address control,uint32 callConfig,address sessionKey,bytes data,bytes signature)"
);

enum UserOperationHashType {
    // this is the default hash type, used for most purposes.
    DEFAULT,
    // this hash type is used when the user operation is trusted
    // and the user operation hash is used as a part of the call chain hash.
    TRUSTED,
    // this hash type is used for ERC-1271 signature verification.
    FULL
}

library CallVerification {
    using CallBits for uint32;

    /// @notice Used to calculate the hash of the UserOperation struct.
    /// @dev The hash is used as an identifier for the UserOperation struct. This can be a more secure,
    /// full hash when trustedOpHash is false. Otherwise, a less secure version of the hash is used.
    /// Usually this is only used for more flexibility when creating the call chain hash.
    /// @param userOp The UserOperation struct to hash.
    /// @param hashType The type of user operation hash to generate.
    /// @return userOpHash The appriate hash of the UserOperation struct.
    function getUserOperationHash(UserOperation memory userOp, UserOperationHashType hashType) internal pure returns (bytes32 userOpHash) {
        if (hashType == UserOperationHashType.TRUSTED) {
            userOpHash = keccak256(
                abi.encodePacked(
                    USER_TYPEHASH_TRUSTED,
                    userOp.from,
                    userOp.to,
                    userOp.dapp,
                    userOp.control,
                    userOp.callConfig,
                    userOp.sessionKey
                )
            );
        } else if (hashType == UserOperationHashType.FULL) {
            userOpHash = keccak256(
                abi.encode(
                    USER_TYPEHASH_FULL,
                    userOp.from,
                    userOp.to,
                    userOp.value,
                    userOp.gas,
                    userOp.maxFeePerGas,
                    userOp.nonce,
                    userOp.deadline,
                    userOp.dapp,
                    userOp.control,
                    userOp.callConfig,
                    userOp.sessionKey,
                    userOp.data,
                    userOp.signature
                )
            );
        } else {
            userOpHash = keccak256(
                abi.encode(
                    USER_TYPEHASH_DEFAULT,
                    userOp.from,
                    userOp.to,
                    userOp.value,
                    userOp.gas,
                    userOp.maxFeePerGas,
                    userOp.nonce,
                    userOp.deadline,
                    userOp.dapp,
                    userOp.control,
                    userOp.callConfig,
                    userOp.sessionKey,
                    userOp.data
                )
            );
        }
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

        if (dConfig.callConfig.needsPreOpsCall()) {
            // Start with preOps call if preOps is needed
            callSequence = abi.encodePacked(dConfig.to);
        }

        // Then user and solver call
        callSequence = abi.encodePacked(callSequence, abi.encode(userOp), abi.encode(solverOps));
        callSequenceHash = keccak256(callSequence);
    }
}
