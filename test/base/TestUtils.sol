// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IDAppControl} from "../../src/contracts/interfaces/IDAppControl.sol";

import "../../src/contracts/types/CallTypes.sol";

library TestUtils {
    // String <> uint16 binary Converter Utility
    function uint16ToBinaryString(uint16 n) public pure returns (string memory) {
        uint256 newN = uint256(n);
        // revert on out of range input
        require(newN < 65536, "n too large");

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

    function computeCallChainHash(
        DAppConfig calldata dConfig,
        UserCall calldata uCall,
        SolverOperation[] calldata solverOps
    ) internal pure returns (bytes32 callSequenceHash) {
        uint256 i;
        if (dConfig.callConfig & 1 << uint32(CallConfigIndex.RequirePreOps) != 0) {
            // Start with preOps call if preOps is needed
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // initial hash = null
                    dConfig.to,
                    abi.encodeWithSelector(IDAppControl.preOpsCall.selector, uCall),
                    i++
                )
            );
        }

        // then user call
        callSequenceHash = keccak256(
            abi.encodePacked(
                callSequenceHash, // always reference previous hash
                abi.encode(uCall),
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
                    abi.encode(solverOps[n].call), // solver call
                    i++
                )
            );
            unchecked {
                ++n;
            }
        }
    }
}
