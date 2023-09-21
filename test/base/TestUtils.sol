// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

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

    // String <> uint32 binary Converter Utility
    function uint32ToBinaryString(uint32 n) public pure returns (string memory) {
        uint256 newN = uint256(n);
        // revert on out of range input
        require(newN < 4294967296, "n too large");

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
}
