//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "src/contracts/interfaces/IDAppControl.sol";
import { Mimic } from "src/contracts/common/Mimic.sol";
import { DAppConfig } from "src/contracts/types/ConfigTypes.sol";
import { UserOperation } from "src/contracts/types/UserOperation.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

/// @title Factory
/// @author FastLane Labs
/// @notice Provides functionality for creating and managing execution environments for DApps within the Atlas Protocol.
/// @dev This contract uses deterministic deployment to generate and manage Execution Environment instances based on
/// predefined templates.
abstract contract Factory {
    address public immutable EXECUTION_ENV_TEMPLATE;
    bytes32 internal immutable _FACTORY_BASE_SALT;

    /// @notice Initializes a new Factory contract instance by setting the immutable salt for deterministic deployment
    /// of Execution Environments and storing the execution template address.
    /// @dev The Execution Environment Template must be separately deployed using the same calculated salt.
    /// @param executionTemplate Address of the pre-deployed execution template contract for creating Execution
    /// Environment instances.
    constructor(address executionTemplate) {
        EXECUTION_ENV_TEMPLATE = executionTemplate;
        _FACTORY_BASE_SALT = keccak256(abi.encodePacked(block.chainid, address(this)));
    }

    /// @notice Creates a new Execution Environment for the caller, given a DAppControl contract address.
    /// @param control The address of the DAppControl contract for which the execution environment is being created.
    /// @return executionEnvironment The address of the newly created Execution Environment instance.
    function createExecutionEnvironment(address control) external returns (address executionEnvironment) {
        uint32 _callConfig = IDAppControl(control).CALL_CONFIG();
        executionEnvironment =
            _getOrCreateExecutionEnvironment({ user: msg.sender, control: control, callConfig: _callConfig });
    }

    /// @notice Retrieves the address and configuration of an existing execution environment for a given user and DApp
    /// control contract.
    /// @param user The address of the user for whom the execution environment is being queried.
    /// @param control The address of the DApp control contract associated with the execution environment.
    /// @return executionEnvironment The address of the queried execution environment.
    /// @return callConfig The call configuration used by the execution environment, retrieved from the DApp control
    /// contract.
    /// @return exists A boolean indicating whether the execution environment already exists (true) or not (false).
    function getExecutionEnvironment(
        address user,
        address control
    )
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists)
    {
        callConfig = IDAppControl(control).CALL_CONFIG();
        executionEnvironment = _getExecutionEnvironmentCustom(user, control, callConfig);
        exists = executionEnvironment.code.length != 0;
    }

    /// @notice Gets an existing execution environment or creates a new one if it does not exist for the specified user
    /// operation.
    /// @param userOp The user operation containing details about the user and the DApp control contract.
    /// @return executionEnvironment The address of the execution environment that was found or created.
    /// @return dConfig The DAppConfig for the execution environment, specifying how operations should be handled.
    function _getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        internal
        returns (address executionEnvironment, DAppConfig memory dConfig)
    {
        dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);
        executionEnvironment = _getOrCreateExecutionEnvironment({
            user: userOp.from,
            control: userOp.control,
            callConfig: dConfig.callConfig
        });
    }

    /// @notice Deploys a new execution environment or retrieves the address of an existing one based on the DApp
    /// control, user, and configuration.
    /// @dev Uses the `create2` opcode for deterministic deployment, allowing the calculation of the execution
    /// environment's address before deployment. The deployment uses a combination of the DAppControl address, user
    /// address, call configuration, and a unique salt to ensure the uniqueness and predictability of the environment's
    /// address.
    /// @param user The address of the user for whom the execution environment is being set.
    /// @param control The address of the DAppControl contract providing the operational context.
    /// @param callConfig CallConfig settings of the DApp control contract.
    /// @return executionEnvironment The address of the newly created or already existing execution environment.
    function _getOrCreateExecutionEnvironment(
        address user,
        address control,
        uint32 callConfig
    )
        internal
        returns (address executionEnvironment)
    {
        bytes memory _creationCode = _getMimicCreationCode({ user: user, control: control, callConfig: callConfig });
        bytes32 _salt = _computeSalt(user, control, callConfig);

        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(abi.encodePacked(_creationCode)))
                    )
                )
            )
        );

        if (executionEnvironment.code.length == 0) {
            assembly {
                executionEnvironment := create2(0, add(_creationCode, 32), mload(_creationCode), _salt)
            }
            emit AtlasEvents.ExecutionEnvironmentCreated(user, executionEnvironment);
        }
    }

    /// @notice Generates the address of a user's execution environment affected by deprecated callConfig changes in the
    /// DAppControl.
    /// @dev Calculates the deterministic address of the execution environment based on the user, control,
    /// callConfig, and controlCodeHash, ensuring consistency across changes in callConfig.
    /// @param user The address of the user for whom the execution environment's address is being generated.
    /// @param control The address of the DAppControl contract associated with the execution environment.
    /// @param callConfig The configuration flags defining the behavior of the execution environment.
    /// @return executionEnvironment The address of the user's execution environment.
    function _getExecutionEnvironmentCustom(
        address user,
        address control,
        uint32 callConfig
    )
        internal
        view
        returns (address executionEnvironment)
    {
        bytes memory _creationCode = _getMimicCreationCode({ user: user, control: control, callConfig: callConfig });
        bytes32 _salt = _computeSalt(user, control, callConfig);

        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(abi.encodePacked(_creationCode)))
                    )
                )
            )
        );
    }

    function _computeSalt(address user, address control, uint32 callConfig) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_FACTORY_BASE_SALT, user, control, callConfig));
    }

    /// @notice Generates the creation code for the execution environment contract.
    /// @param control The address of the DAppControl contract associated with the execution environment.
    /// @param callConfig The configuration flags defining the behavior of the execution environment.
    /// @param user The address of the user for whom the execution environment is being created, contributing to the
    /// uniqueness of the creation code.
    /// @return creationCode The bytecode representing the creation code of the execution environment contract.
    function _getMimicCreationCode(
        address user,
        address control,
        uint32 callConfig
    )
        internal
        view
        returns (bytes memory creationCode)
    {
        address _executionLib = EXECUTION_ENV_TEMPLATE;
        // NOTE: Changing compiler settings or solidity versions can break this.
        creationCode = type(Mimic).creationCode;

        assembly {
            mstore(
                add(creationCode, 85),
                or(
                    and(mload(add(creationCode, 85)), not(shl(96, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))),
                    shl(96, _executionLib)
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
                    add(shl(96, control), add(shl(88, 0x63), shl(56, callConfig)))
                )
            )
        }
    }
}
