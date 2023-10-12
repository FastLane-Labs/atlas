//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ExecutionPhase} from "../types/LockTypes.sol";

import {CallBits} from "../libraries/CallBits.sol";

import {GovernanceControl} from "./GovernanceControl.sol";
import {ExecutionBase} from "../common/ExecutionBase.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import "forge-std/Test.sol";

// TODO: Check payable is appropriate in pre/post ops and solver calls. Needed to send ETH if necessary (even when delegatecalled)

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
    function preOpsCall(UserOperation calldata userOp)
        external
        payable
        onlyActiveEnvironment
        validControl
        validPhase(ExecutionPhase.PreOps)
        validDepth(1)
        returns (bytes memory)
    {
        return _preOpsCall(userOp);
    }

    function preSolverCall(bytes calldata data) 
        external
        payable
        onlyActiveEnvironment
        validControl
        validPhase(ExecutionPhase.SolverOperations)
        validDepth(1)
        returns (bool)
    {
        return _preSolverCall(data);
    }

    function postSolverCall(bytes calldata data) 
        external
        payable
        onlyActiveEnvironment
        validControl
        validPhase(ExecutionPhase.SolverOperations)
        validDepth(1)
        returns (bool)
    {
        
        return _postSolverCall(data);
    }

    function allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) 
        external 
        onlyActiveEnvironment
        validControl
        validPhase(ExecutionPhase.HandlingPayments)
        validDepth(1)
    {
        _allocateValueCall(bidToken, bidAmount, data);
    }

    function postOpsCall(bytes calldata data) 
        external
        payable
        onlyActiveEnvironment
        validControl
        validPhase(ExecutionPhase.PostOps)
        validDepth(1)
        returns (bool) 
    {
        return _postOpsCall(data);
    }

    // View functions
    function userDelegated() external view returns (bool delegated) {
        delegated = CallBits.needsDelegateUser(callConfig);
    }

    function requireSequencedNonces() external view returns (bool isSequenced) {
        isSequenced = CallBits.needsSequencedNonces(callConfig);
    }

    function getDAppConfig(UserOperation calldata userOp) 
        mustBeCalled 
        external 
        view  
        returns (DAppConfig memory dConfig) 
    {
        dConfig = DAppConfig({
            to: address(this),
            callConfig: callConfig,
            bidToken: getBidFormat(userOp)
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
