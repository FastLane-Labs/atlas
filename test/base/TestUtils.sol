// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IDAppControl } from "../../src/contracts/interfaces/IDAppControl.sol";
import { Mimic } from "../../src/contracts/atlas/Mimic.sol";

import "../../src/contracts/types/UserCallTypes.sol";
import "../../src/contracts/types/SolverCallTypes.sol";
import "../../src/contracts/types/DAppApprovalTypes.sol";

library TestUtils {
    // String <> uint16 binary Converter Utility
    function uint16ToBinaryString(uint16 n) public pure returns (string memory) {
        uint256 newN = uint256(n);
        // revert on out of range input
        require(newN < 65_536, "n too large");

        bytes memory output = new bytes(16);

        uint256 i = 0;
        for (; i < 16; i++) {
            if (newN == 0) {
                // Now that we've filled in the last 1, fill rest of 0s in
                for (; i < 16; i++) {
                    output[15 - i] = bytes1("0");
                }
                break;
            }
            output[15 - i] = (newN % 2 == 1) ? bytes1("1") : bytes1("0");
            newN /= 2;
        }
        return string(output);
    }

    // String <> uint32 binary Converter Utility
    function uint32ToBinaryString(uint32 n) public pure returns (string memory) {
        uint256 newN = uint256(n);
        // revert on out of range input
        require(newN < 4_294_967_296, "n too large");

        bytes memory output = new bytes(32);

        uint256 i = 0;
        for (; i < 32; i++) {
            if (newN == 0) {
                // Now that we've filled in the last 1, fill rest of 0s in
                for (; i < 32; i++) {
                    output[31 - i] = bytes1("0");
                }
                break;
            }
            output[31 - i] = (newN % 2 == 1) ? bytes1("1") : bytes1("0");
            newN /= 2;
        }
        return string(output);
    }

    // String <> uint256 binary Converter Utility
    function uint256ToBinaryString(uint256 n) public pure returns (string memory) {
        bytes memory output = new bytes(256);

        uint256 i = 0;
        for (; i < 256; i++) {
            if (n == 0) {
                // Now that we've filled in the last 1, fill rest of 0s in
                for (; i < 256; i++) {
                    output[255 - i] = bytes1("0");
                }
                break;
            }
            output[255 - i] = (n % 2 == 1) ? bytes1("1") : bytes1("0");
            n /= 2;
        }
        return string(output);
    }

    function _getMimicCreationCode(
        address controller,
        uint32 callConfig,
        address executionLib,
        address user,
        bytes32 controlCodeHash
    )
        internal
        pure
        returns (bytes memory creationCode)
    {
        // NOTE: Changing compiler settings or solidity versions can break this.
        creationCode = type(Mimic).creationCode;

        // TODO: unpack the SHL and reorient
        assembly {
            mstore(
                add(creationCode, 85),
                or(
                    and(mload(add(creationCode, 85)), not(shl(96, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))),
                    shl(96, executionLib)
                )
            )

            mstore(
                add(creationCode, 118),
                or(
                    and(mload(add(creationCode, 118)), not(shl(96, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))),
                    shl(96, user)
                )
            )

            mstore(
                add(creationCode, 139),
                or(
                    and(
                        mload(add(creationCode, 139)),
                        not(shl(56, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFF))
                    ),
                    add(shl(96, controller), add(shl(88, 0x63), shl(56, callConfig)))
                )
            )

            mstore(add(creationCode, 165), controlCodeHash)
        }
    }

    function computeCallChainHash(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps
    )
        internal
        pure
        returns (bytes32 callSequenceHash)
    {
        uint256 i;
        if (dConfig.callConfig & 1 << uint32(CallConfigIndex.RequirePreOps) != 0) {
            // Start with preOps call if preOps is needed
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // initial hash = null
                    dConfig.to,
                    abi.encodeWithSelector(IDAppControl.preOpsCall.selector, userOp),
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
        uint256 n;
        for (; n < count;) {
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // reference previous hash
                    abi.encode(solverOps[n]), // solver call
                    i++
                )
            );
            unchecked {
                ++n;
            }
        }
    }
}
