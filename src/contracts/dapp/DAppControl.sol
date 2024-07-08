//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControlTemplate } from "./ControlTemplate.sol";
import { ExecutionBase } from "src/contracts/common/ExecutionBase.sol";
import { ExecutionPhase } from "src/contracts/types/LockTypes.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/ConfigTypes.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";

/// @title DAppControl
/// @author FastLane Labs
/// @notice DAppControl is the base contract which should be inherited by any Atlas dApps.
/// @notice Storage variables (except immutable) will be defaulted if accessed by delegatecalls.
/// @notice If an extension DAppControl uses storage variables, those should not be accessed by delegatecalls.
abstract contract DAppControl is DAppControlTemplate, ExecutionBase {
    using CallBits for uint32;

    uint8 private constant _CONTROL_DEPTH = 1 << 2;

    uint32 public immutable CALL_CONFIG;
    address public immutable CONTROL;
    address public immutable ATLAS_VERIFICATION;

    address public governance;
    address public pendingGovernance;

    constructor(address atlas, address initialGovernance, CallConfig memory callConfig) ExecutionBase(atlas) {
        if (callConfig.userNoncesSequential && callConfig.dappNoncesSequential) {
            // Max one of user or dapp nonces can be sequential, not both
            revert AtlasErrors.BothUserAndDAppNoncesCannotBeSequential();
        }
        if (callConfig.trackPreOpsReturnData && callConfig.trackUserReturnData) {
            // Max one of preOps or userOp return data can be tracked, not both
            revert AtlasErrors.BothPreOpsAndUserReturnDataCannotBeTracked();
        }
        if (callConfig.invertBidValue && callConfig.exPostBids) {
            // If both invertBidValue and exPostBids are true, solver's retreived bid cannot be determined
            revert AtlasErrors.InvertBidValueCannotBeExPostBids();
        }
        CALL_CONFIG = CallBits.encodeCallConfig(callConfig);
        CONTROL = address(this);
        ATLAS_VERIFICATION = IAtlas(atlas).VERIFICATION();

        governance = initialGovernance;
    }

    // Safety and support functions and modifiers that make the relationship between dApp
    // and FastLane's backend trustless.

    // Modifiers
    modifier validControl() {
        if (CONTROL != _control()) revert AtlasErrors.InvalidControl();
        _;
    }

    // Reverts if phase in Atlas is not the specified phase.
    // This is required to prevent reentrancy in hooks from other hooks in different phases.
    modifier onlyPhase(ExecutionPhase phase) {
        (,, uint8 atlasPhase) = IAtlas(ATLAS).lock();
        if (atlasPhase != uint8(phase)) revert AtlasErrors.WrongPhase();
        _;
    }

    modifier mustBeCalled() {
        if (address(this) != CONTROL) revert AtlasErrors.NoDelegatecall();
        _;
    }

    /// @notice The preOpsCall hook which may be called before the UserOperation is executed.
    /// @param userOp The UserOperation struct.
    /// @return data Data to be passed to the next call phase.
    function preOpsCall(UserOperation calldata userOp)
        external
        payable
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PreOps)
        returns (bytes memory)
    {
        return _preOpsCall(userOp);
    }

    /// @notice The preSolverCall hook which may be called before the SolverOperation is executed.
    /// @dev Should revert if any DApp-specific checks fail to indicate non-fulfillment.
    /// @param solverOp The SolverOperation to be executed after this hook has been called.
    /// @param returnData Data returned from the previous call phase.
    function preSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PreSolver)
    {
        _preSolverCall(solverOp, returnData);
    }

    /// @notice The postSolverCall hook which may be called after the SolverOperation has been executed.
    /// @dev Should revert if any DApp-specific checks fail to indicate non-fulfillment.
    /// @param solverOp The SolverOperation struct that was executed just before this hook was called.
    /// @param returnData Data returned from the previous call phase.
    function postSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PostSolver)
    {
        _postSolverCall(solverOp, returnData);
    }

    /// @notice The allocateValueCall hook which is called after a successful SolverOperation.
    /// @param bidToken The address of the token used for the winning SolverOperation's bid.
    /// @param bidAmount The winning bid amount.
    /// @param data Data returned from the previous call phase.
    function allocateValueCall(
        address bidToken,
        uint256 bidAmount,
        bytes calldata data
    )
        external
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.AllocateValue)
    {
        _allocateValueCall(bidToken, bidAmount, data);
    }

    /// @notice The postOpsCall hook which may be called as the last phase of a `metacall` transaction.
    /// @param solved Boolean indicating whether a winning SolverOperation was executed successfully.
    /// @param data Data returned from the previous call phase.
    function postOpsCall(
        bool solved,
        bytes calldata data
    )
        external
        payable
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PostOps)
    {
        _postOpsCall(solved, data);
    }

    function userDelegated() external view returns (bool delegated) {
        delegated = CALL_CONFIG.needsDelegateUser();
    }

    function requireSequentialUserNonces() external view returns (bool isSequential) {
        isSequential = CALL_CONFIG.needsSequentialUserNonces();
    }

    function requireSequentialDAppNonces() external view returns (bool isSequential) {
        isSequential = CALL_CONFIG.needsSequentialDAppNonces();
    }

    /// @notice Returns the DAppConfig struct of this DAppControl contract.
    /// @param userOp The UserOperation struct.
    /// @return dConfig The DAppConfig struct of this DAppControl contract.
    function getDAppConfig(UserOperation calldata userOp)
        external
        view
        mustBeCalled
        returns (DAppConfig memory dConfig)
    {
        dConfig = DAppConfig({
            to: address(this),
            callConfig: CALL_CONFIG,
            bidToken: getBidFormat(userOp),
            solverGasLimit: getSolverGasLimit()
        });
    }

    /// @notice Returns the CallConfig struct of this DAppControl contract.
    /// @return The CallConfig struct of this DAppControl contract.
    function getCallConfig() external view returns (CallConfig memory) {
        return _getCallConfig();
    }

    function _getCallConfig() internal view returns (CallConfig memory) {
        return CALL_CONFIG.decodeCallConfig();
    }

    /// @notice Returns the current governance address of this DAppControl contract.
    /// @return The address of the current governance account of this DAppControl contract.
    function getDAppSignatory() external view mustBeCalled returns (address) {
        return governance;
    }

    /// @notice Starts the transfer of governance to a new address. Only callable by the current governance address.
    /// @param newGovernance The address of the new governance.
    function transferGovernance(address newGovernance) external mustBeCalled {
        if (msg.sender != governance) {
            revert AtlasErrors.OnlyGovernance();
        }
        pendingGovernance = newGovernance;
        emit AtlasEvents.GovernanceTransferStarted(governance, newGovernance);
    }

    /// @notice Accepts the transfer of governance to a new address. Only callable by the new governance address.
    function acceptGovernance() external mustBeCalled {
        address newGovernance = pendingGovernance;
        if (msg.sender != newGovernance) {
            revert AtlasErrors.Unauthorized();
        }

        address prevGovernance = governance;
        governance = newGovernance;
        delete pendingGovernance;

        IAtlasVerification(ATLAS_VERIFICATION).changeDAppGovernance(prevGovernance, newGovernance);

        emit AtlasEvents.GovernanceTransferred(prevGovernance, newGovernance);
    }
}
