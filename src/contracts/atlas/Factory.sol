//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Clones } from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import { IDAppControl } from "src/contracts/interfaces/IDAppControl.sol";
import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
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
    /// @param _executionTemplate Address of the pre-deployed execution template contract for creating Execution
    /// Environment instances.
    constructor(address _executionTemplate) {
        EXECUTION_ENV_TEMPLATE = _executionTemplate;
        _FACTORY_BASE_SALT = keccak256(abi.encodePacked(block.chainid, address(this)));
    }

    /// @notice Creates a new Execution Environment for the caller, given a DAppControl contract address.
    /// @param control The address of the DAppControl contract for which the execution environment is being created.
    /// @return executionEnvironment The address of the newly created Execution Environment instance.
    function createExecutionEnvironment(address control) external returns (address executionEnvironment) {
        executionEnvironment = _getOrCreateExecutionEnvironment({ user: msg.sender, control: control });
    }

    /// @notice Retrieves the address and configuration of an existing execution environment for a given user and DApp
    /// control contract.
    /// @param user The address of the user for whom the execution environment is being queried.
    /// @param control The address of the DAppControl contract associated with the execution environment.
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
        executionEnvironment = _getExecutionEnvironmentCustom({ user: user, control: control, callConfig: callConfig });
        exists = executionEnvironment.code.length != 0;
    }

    /// @notice Gets an existing execution environment or creates a new one if it does not exist for the specified user
    /// operation.
    /// @param userOp The user operation containing details about the user and the DApp control contract.
    /// @return executionEnvironment The address of the execution environment that was found or created.
    /// @return dAppConfig The DAppConfig for the execution environment, specifying how operations should be handled.
    function _getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        internal
        returns (address executionEnvironment, DAppConfig memory dAppConfig)
    {
        dAppConfig = IDAppControl(userOp.control).getDAppConfig(userOp);
        executionEnvironment = _getOrCreateExecutionEnvironment({ user: userOp.from, control: userOp.control });
    }

    function _getOrCreateExecutionEnvironment(
        address user,
        address control
    )
        internal
        returns (address executionEnvironment)
    {
        uint32 callConfig = IDAppControl(control).CALL_CONFIG();
        bytes32 salt = _computeSalt(user, control, callConfig);

        executionEnvironment = Clones.predictDeterministicAddress({
            implementation: EXECUTION_ENV_TEMPLATE,
            salt: salt,
            deployer: address(this)
        });

        // If no contract deployed at the predicted Execution Environment address, deploy a new one
        if (executionEnvironment.code.length == 0) {
            executionEnvironment = Clones.cloneDeterministic({ implementation: EXECUTION_ENV_TEMPLATE, salt: salt });

            emit AtlasEvents.ExecutionEnvironmentCreated(user, executionEnvironment);
        }
    }

    /// @notice Predicts the address of a user's execution environment given the user, control, and callConfig salt
    /// inputs. NOTE: This is useful when the control contract is mutable and the callConfig may have changed, as the
    /// callConfig passed must match that of the control contract when the Execution Environment was created.
    /// @param user The address of the user who created the execution environment.
    /// @param control The address of the DAppControl contract associated with the execution environment.
    /// @param callConfig The CallConfig settings of the DAppControl contract associated with the execution environment.
    /// @return executionEnvironment The predicted address of the user's execution environment.
    function _getExecutionEnvironmentCustom(
        address user,
        address control,
        uint32 callConfig
    )
        internal
        view
        returns (address executionEnvironment)
    {
        executionEnvironment = Clones.predictDeterministicAddress({
            implementation: EXECUTION_ENV_TEMPLATE,
            salt: _computeSalt(user, control, callConfig),
            deployer: address(this)
        });
    }

    /// @notice Computes the salt for deterministic deployment of Execution Environments based on the user, control, and
    /// callConfig inputs.
    /// @param user The address of the user creating the execution environment.
    /// @param control The address of the DAppControl contract associated with the execution environment.
    /// @param callConfig The CallConfig settings of the DAppControl contract associated with the execution environment.
    /// @return salt The computed salt for deterministic deployment of the Execution Environment.
    function _computeSalt(address user, address control, uint32 callConfig) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_FACTORY_BASE_SALT, user, control, callConfig));
    }
}
