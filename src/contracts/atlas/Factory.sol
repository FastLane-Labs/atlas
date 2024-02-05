//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { Mimic } from "./Mimic.sol";
import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../types/UserCallTypes.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "forge-std/Test.sol";

abstract contract Factory {
    bytes32 public immutable salt;
    address public immutable executionTemplate;

    // NOTE: The ExecutionEnvironment Template must be separately deployed using the same salt as calculated below
    constructor(address _executionTemplate) {
        salt = keccak256(abi.encodePacked(block.chainid, address(this), "AtlasFactory 1.0"));
        executionTemplate = _executionTemplate;
    }

    // ------------------ //
    // EXTERNAL FUNCTIONS //
    // ------------------ //

    function createExecutionEnvironment(address dAppControl) external returns (address executionEnvironment) {
        uint32 callConfig = IDAppControl(dAppControl).callConfig();
        executionEnvironment = _setExecutionEnvironment(dAppControl, msg.sender, callConfig, dAppControl.codehash);
    }

    function getExecutionEnvironment(
        address user,
        address dAppControl
    )
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists)
    {
        callConfig = IDAppControl(dAppControl).callConfig();
        executionEnvironment = _getExecutionEnvironmentCustom(user, dAppControl.codehash, dAppControl, callConfig);
        exists = executionEnvironment.codehash != bytes32(0);
    }

    // ------------------ //
    // INTERNAL FUNCTIONS //
    // ------------------ //

    function _getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        internal
        returns (address executionEnvironment, DAppConfig memory dConfig)
    {
        address control = userOp.control;
        dConfig = IDAppControl(control).getDAppConfig(userOp);
        executionEnvironment = _setExecutionEnvironment(control, userOp.from, dConfig.callConfig, control.codehash);
    }

    function _setExecutionEnvironment(
        address dAppControl,
        address user,
        uint32 callConfig,
        bytes32 controlCodeHash
    )
        internal
        returns (address executionEnvironment)
    {
        bytes memory creationCode = _getMimicCreationCode(dAppControl, callConfig, user, controlCodeHash);

        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(abi.encodePacked(creationCode)))
                    )
                )
            )
        );

        if (executionEnvironment.codehash == bytes32(0)) {
            bytes32 memSalt = salt;
            assembly {
                executionEnvironment := create2(0, add(creationCode, 32), mload(creationCode), memSalt)
            }
            emit AtlasEvents.ExecutionEnvironmentCreated(user, executionEnvironment);
        }
    }

    // NOTE: This func is used to generate the address of user ExecutionEnvironments that have
    // been deprecated due to DAppControl changes of callConfig.
    function _getExecutionEnvironmentCustom(
        address user,
        bytes32 controlCodeHash,
        address controller,
        uint32 callConfig
    )
        internal
        view
        returns (address executionEnvironment)
    {
        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(_getMimicCreationCode(controller, callConfig, user, controlCodeHash))
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
        address user,
        bytes32 controlCodeHash
    )
        internal
        view
        returns (bytes memory creationCode)
    {
        address executionLib = executionTemplate;
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
}
