//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { DAppControlTemplate } from "./ControlTemplate.sol";
import { ExecutionBase } from "../common/ExecutionBase.sol";
import { EXECUTION_PHASE_OFFSET } from "../libraries/SafetyBits.sol";
import { ExecutionPhase } from "../types/LockTypes.sol";
import { CallBits } from "../libraries/CallBits.sol";
import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";

import "forge-std/Test.sol";

abstract contract DAppControl is DAppControlTemplate, ExecutionBase {
    uint8 private constant _CONTROL_DEPTH = 1 << 2;

    uint32 public immutable CALL_CONFIG;
    address public immutable CONTROL;
    address public immutable ATLAS_VERIFICATION;

    address public governance;
    address public pendingGovernance;

    constructor(address _atlas, address _governance, CallConfig memory _callConfig) ExecutionBase(_atlas) {
        if (_callConfig.userNoncesSequenced && _callConfig.dappNoncesSequenced) {
            // Max one of user or dapp nonces can be sequenced, not both
            revert AtlasErrors.BothUserAndDAppNoncesCannotBeSequenced();
        }
        CONTROL = address(this);
        CALL_CONFIG = CallBits.encodeCallConfig(_callConfig);
        governance = _governance;
    }

    // Safety and support functions and modifiers that make the relationship between dApp
    // and FastLane's backend trustless.

    // Modifiers
    modifier validControl() {
        if (CONTROL != _control()) revert AtlasErrors.InvalidControl();
        _;
    }

    modifier mustBeCalled() {
        if (address(this) != CONTROL) revert AtlasErrors.NoDelegatecall();
        _;
    }

    // Functions
    function preOpsCall(UserOperation calldata userOp)
        external
        payable
        validControl
        onlyAtlasEnvironment(ExecutionPhase.PreOps, _CONTROL_DEPTH)
        returns (bytes memory)
    {
        return _preOpsCall(userOp);
    }

    function preSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        validControl
        onlyAtlasEnvironment(ExecutionPhase.PreSolver, _CONTROL_DEPTH)
        returns (bool)
    {
        return _preSolverCall(solverOp, returnData);
    }

    function postSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        validControl
        onlyAtlasEnvironment(ExecutionPhase.PostSolver, _CONTROL_DEPTH)
        returns (bool)
    {
        return _postSolverCall(solverOp, returnData);
    }

    function allocateValueCall(
        address bidToken,
        uint256 bidAmount,
        bytes calldata data
    )
        external
        validControl
        onlyAtlasEnvironment(ExecutionPhase.HandlingPayments, _CONTROL_DEPTH)
    {
        _allocateValueCall(bidToken, bidAmount, data);
    }

    function postOpsCall(
        bool solved,
        bytes calldata data
    )
        external
        payable
        validControl
        onlyAtlasEnvironment(ExecutionPhase.PostOps, _CONTROL_DEPTH)
        returns (bool)
    {
        return _postOpsCall(solved, data);
    }

    // View functions
    function userDelegated() external view returns (bool delegated) {
        delegated = CallBits.needsDelegateUser(CALL_CONFIG);
    }

    function requireSequencedUserNonces() external view returns (bool isSequenced) {
        isSequenced = CallBits.needsSequencedUserNonces(CALL_CONFIG);
    }

    function requireSequencedDAppNonces() external view returns (bool isSequenced) {
        isSequenced = CallBits.needsSequencedDAppNonces(CALL_CONFIG);
    }

    function getDAppConfig(UserOperation calldata userOp)
        external
        view
        mustBeCalled
        returns (DAppConfig memory dConfig)
    {
        dConfig = DAppConfig({ to: address(this), callConfig: CALL_CONFIG, bidToken: getBidFormat(userOp) });
    }

    function getCallConfig() external view returns (CallConfig memory) {
        return _getCallConfig();
    }

    function _getCallConfig() internal view returns (CallConfig memory) {
        return CallBits.decodeCallConfig(CALL_CONFIG);
    }

    function getDAppSignatory() external view returns (address) {
        return governance;
    }

    // Governance functions

    function transferGovernance(address newGovernance) external {
        if (msg.sender != governance) {
            revert AtlasErrors.OnlyGovernance();
        }
        pendingGovernance = newGovernance;
        emit AtlasEvents.GovernanceTransferStarted(governance, newGovernance);
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernance) {
            revert AtlasErrors.Unauthorized();
        }
        address prevGovernance = governance;
        governance = pendingGovernance;
        delete pendingGovernance;
        emit AtlasEvents.GovernanceTransferred(prevGovernance, governance);
    }
}
