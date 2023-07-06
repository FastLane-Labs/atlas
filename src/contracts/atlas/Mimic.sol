//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

contract Mimic {
    /*
    0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa is standin for the ExecutionEnvironment, which is a de facto library
    0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB is standin for the user's EOA address
    0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC is standin for the protocol control address
    0x2222 is standin for the call configuration

    These values are adjusted by the factory to match the appropriate values for the intended user/control/config.
    This happens during contract creation.

        creationCode = type(Mimic).creationCode;
        assembly {
            mstore(add(creationCode, 85), add(
                shl(96, executionLib), 
                0x73ffffffffffffffffffffff
            ))
            mstore(add(creationCode, 131), add(
                shl(96, user), 
                0x73ffffffffffffffffffffff
            ))
            mstore(add(creationCode, 152), add(
                shl(96, protocolControl), 
                add(
                    add(
                        shl(88, 0x61), 
                        shl(72, callConfig)
                    ),
                    0x604051602001610082
                )
            ))
        }
    */

    receive() external payable {}

    fallback(bytes calldata) external payable returns (bytes memory) {
        (bool success, bytes memory output) = address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa).delegatecall(
            abi.encodePacked(
                msg.data, 
                address(0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB),
                address(0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC),
                uint16(0x2222)
            )
        );
        if (!success) { revert(); }
        return output;
    }
}