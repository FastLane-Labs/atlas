// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IDAppControl} from "../../src/contracts/interfaces/IDAppControl.sol";
import {Factory} from "../../src/contracts/atlas/Factory.sol";
import {Mimic} from "../../src/contracts/atlas/Mimic.sol";

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

    function computeExecutionEnvironment(address payable atlas, UserOperation calldata userOp, address controller)
        public
        view
        returns (address executionEnvironment)
    {
        DAppConfig memory dConfig = IDAppControl(controller).getDAppConfig();

        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            atlas,
                            Factory(atlas).salt(),
                            keccak256(
                                abi.encodePacked(
                                    _getMimicCreationCode(
                                        controller,
                                        dConfig.callConfig,
                                        Factory(atlas).execution(),
                                        userOp.call.from,
                                        controller.codehash
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    function _getMimicCreationCode(
        address controller,
        uint32 callConfig,
        address executionLib,
        address user,
        bytes32 controlCodeHash
    ) internal pure returns (bytes memory creationCode) {
        // NOTE: Changing compiler settings or solidity versions can break this.
        creationCode = type(Mimic).creationCode;
        assembly {
            mstore(add(creationCode, 85), add(shl(96, executionLib), 0x73ffffffffffffffffffffff))
            mstore(add(creationCode, 131), add(shl(96, user), 0x73ffffffffffffffffffffff))
            mstore(
                add(creationCode, 152),
                add(shl(96, controller), add(add(shl(88, 0x63), shl(56, callConfig)), 0x7f000000000000))
            )
            mstore(add(creationCode, 178), controlCodeHash)
        }
    }
}
