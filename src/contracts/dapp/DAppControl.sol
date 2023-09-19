//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ExecutionPhase} from "../types/LockTypes.sol";

import {CallBits} from "../libraries/CallBits.sol";

import {GovernanceControl} from "./GovernanceControl.sol";
import {ExecutionBase} from "../common/ExecutionBase.sol";

import "../types/CallTypes.sol";

import "forge-std/Test.sol";

abstract contract DAppControl is Test, GovernanceControl, ExecutionBase {
    address public immutable escrow;
    address public immutable governance;
    address public immutable control;
    uint32 public immutable callConfig;

    constructor(
        address _escrow,
        address _governance,
        CallConfig memory _callConfig
    ) ExecutionBase(_escrow) {
        control = address(this);
        escrow = _escrow;
        governance = _governance;
        callConfig = CallBits.encodeCallConfig(_callConfig);
    }

    // Safety and support functions and modifiers that make the relationship between dApp
    // and FastLane's backend trustless.

    // Modifiers
    modifier validControl() {
        require(control == _control(), "ERR-PC050 InvalidControl");
        _;
    }

    modifier mustBeCalled() {
        require(address(this) == control, "ERR-PC052 MustBeCalled");
        _;
    }

    // Functions
    function preOpsCall(UserCall calldata uCall)
        external
        onlyAtlasEnvironment
        validControl
        validPhase(ExecutionPhase.PreOps)
        returns (bytes memory)
    {
        return _preOpsCall(uCall);
    }

    function userLocalCall(bytes calldata data) 
        external 
        onlyAtlasEnvironment
        validControl
        validPhase(ExecutionPhase.UserOperation)
        returns (bytes memory) 
    {
        return CallBits.needsDelegateUser(callConfig) ? _userLocalDelegateCall(data) : _userLocalStandardCall(data);
    }

    function preSolverCall(bytes calldata data) 
        external 
        onlyAtlasEnvironment
        validControl
        validPhase(ExecutionPhase.SolverOperations)
        returns (bool)
    {
        return _preSolverCall(data);
    }

    function postSolverCall(bytes calldata data) 
        external 
        onlyAtlasEnvironment
        validControl
        validPhase(ExecutionPhase.SolverOperations)
        returns (bool)
    {
        
        return _postSolverCall(data);
    }

    function allocateValueCall(bytes calldata data) 
        external 
        onlyAtlasEnvironment
        validControl
        validPhase(ExecutionPhase.HandlingPayments)
    {
        return _allocateValueCall(data);
    }

    function postOpsCall(bytes calldata data) 
        external 
        onlyAtlasEnvironment
        validControl
        validPhase(ExecutionPhase.PostOps)
        returns (bool) 
    {
        return _postOpsCall(data);
    }

    function validateUserOperation(UserCall calldata uCall) 
        external 
        view
        onlyAtlasEnvironment
        validControl
        returns (bool) 
    {
        return _validateUserOperation(uCall);
    }

    // View functions
    function userDelegated() external view returns (bool delegated) {
        delegated = CallBits.needsDelegateUser(callConfig);
    }

    function userLocal() external view returns (bool local) {
        local = CallBits.needsLocalUser(callConfig);
    }

    function userDelegatedLocal() external view returns (bool delegated, bool local) {
        delegated = CallBits.needsDelegateUser(callConfig);
        local = CallBits.needsLocalUser(callConfig);
    }

    function requireSequencedNonces() external view returns (bool isSequenced) {
        isSequenced = CallBits.needsSequencedNonces(callConfig);
    }

    function getDAppConfig() external view returns (DAppConfig memory dConfig) {
        dConfig = DAppConfig({
            to: address(this),
            callConfig: callConfig
        });
    }

    function _getCallConfig() internal view returns (CallConfig memory) {
        return CallBits.decodeCallConfig(callConfig);
    }

    function getCallConfig() external view returns (CallConfig memory) {
        return _getCallConfig();
    }

    function getDAppSignatory() external view returns (address governanceAddress) {
        governanceAddress = governance;
    }
}
