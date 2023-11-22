//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { Mimic } from "./Mimic.sol";
import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";

// TODO make sure no cases of address(this) when Atlas address is intended

contract AtlasFactory {
    event NewExecutionEnvironment(
        address indexed environment, address indexed user, address indexed controller, uint32 callConfig
    );

    bytes32 public immutable salt;
    address public immutable executionTemplate;
    address public immutable atlas;

    constructor(address _atlas) {
        salt = keccak256(abi.encodePacked(block.chainid, address(this), "AtlasFactory 1.0"));
        atlas = _atlas;

        executionTemplate = _deployExecutionEnvironmentTemplate(_atlas);
    }

    // ------------------ //
    // EXTERNAL FUNCTIONS //
    // ------------------ //

    function createExecutionEnvironment(
        address account,
        address dAppControl
    )
        external
        returns (address executionEnvironment)
    {
        // Must call createExecutionEnvironment on Atlas contract to properly initialize nonce tracking
        require(msg.sender == atlas, "AtlasFactory: Only Atlas can create execution environments");
        executionEnvironment = _setExecutionEnvironment(dAppControl, account, dAppControl.codehash);
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

    function getExecutionEnvironmentCustom(
        address user,
        bytes32 controlCodeHash,
        address controller,
        uint32 callConfig
    )
        external
        view
        returns (address executionEnvironment)
    {
        executionEnvironment = _getExecutionEnvironmentCustom(user, controlCodeHash, controller, callConfig);
    }

    function getMimicCreationCode(
        address controller,
        uint32 callConfig,
        address user,
        bytes32 controlCodeHash
    )
        external
        view
        returns (bytes memory creationCode)
    {
        creationCode = _getMimicCreationCode(controller, callConfig, user, controlCodeHash);
    }

    // ------------------ //
    // INTERNAL FUNCTIONS //
    // ------------------ //

    function _deployExecutionEnvironmentTemplate(address _atlas) internal returns (address executionEnvironment) {
        ExecutionEnvironment _environment = new ExecutionEnvironment{
            salt: salt
        }(_atlas);

        executionEnvironment = address(_environment);
    }

    function _setExecutionEnvironment(
        address dAppControl,
        address user,
        bytes32 controlCodeHash
    )
        internal
        returns (address executionEnvironment)
    {
        uint32 callConfig = IDAppControl(dAppControl).callConfig();

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

            emit NewExecutionEnvironment(executionEnvironment, user, dAppControl, callConfig);
        }
    }

    function _getExecutionEnvironment(
        address user,
        bytes32 controlCodeHash,
        address controller
    )
        internal
        view
        returns (address executionEnvironment)
    {
        uint32 callConfig = IDAppControl(controller).callConfig();
        executionEnvironment = _getExecutionEnvironmentCustom(user, controlCodeHash, controller, callConfig);
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
