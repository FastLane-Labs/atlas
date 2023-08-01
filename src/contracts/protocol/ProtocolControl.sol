//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {CallBits} from "../libraries/CallBits.sol";

import {GovernanceControl} from "./GovernanceControl.sol";
import {ExecutionBase} from "./ExecutionBase.sol";

import "../types/CallTypes.sol";

import "forge-std/Test.sol";

abstract contract ProtocolControl is Test, GovernanceControl, ExecutionBase {
    address public immutable escrow;
    address public immutable governance;
    address public immutable control;

    bool public immutable sequenced;
    bool public immutable requireStaging;
    bool public immutable delegateStaging;
    bool public immutable localUser;
    bool public immutable delegateUser;
    bool public immutable delegateAllocating;
    bool public immutable requireVerification;
    bool public immutable delegateVerification;
    bool public immutable recycledStorage;

    constructor(
        address escrowAddress,
        address governanceAddress,
        bool shouldRequireSequencedNonces,
        bool shouldRequireStaging,
        bool shouldDelegateStaging,
        bool shouldExecuteUserLocally,
        bool shouldDelegateUser,
        bool shouldDelegateAllocating,
        bool shouldRequireVerification,
        bool shouldDelegateVerification,
        bool allowRecycledStorage
    ) {
        control = address(this);

        sequenced = shouldRequireSequencedNonces;


        if (shouldDelegateStaging) {
            require(shouldRequireStaging, "ERR-GC04 InvalidStaging");
        }

        if (shouldDelegateVerification) {
            require(shouldRequireVerification, "ERR-GC05 InvalidVerification");
        }

        require(shouldDelegateAllocating, "ERR-GC02 NotDelegateAllocating");

        if (shouldDelegateUser) {
            require(shouldExecuteUserLocally, "ERR-GC03 SelfDelegating");
            // TODO: Consider allowing
        }

        escrow = escrowAddress;
        governance = governanceAddress;

        requireStaging = shouldRequireStaging;
        delegateStaging = shouldDelegateStaging;
        localUser = shouldExecuteUserLocally;
        delegateUser = shouldDelegateUser;
        delegateAllocating = shouldDelegateAllocating;
        requireVerification = shouldRequireVerification;
        delegateVerification = shouldDelegateVerification;
        recycledStorage = allowRecycledStorage;
    }

    // Safety and support functions and modifiers that make the relationship between protocol
    // and FastLane's backend trustless.
    modifier onlyApprovedCaller(bool isDelegated) {
        if (isDelegated) {
            require(msg.sender == escrow, "ERR-PC060 InvalidCaller");
        } else {
            require(msg.sender == ISafetyLocks(escrow).approvedCaller(), "ERR-PC061 InvalidCaller");
        }
        _;
    }

    function stageCall(address to, address from, bytes4 userSelector, bytes calldata userData)
        external
        onlyApprovedCaller(delegateStaging)
        returns (bytes memory)
    {
        return _stageCall(to, from, userSelector, userData);
    }

    function userLocalCall(bytes calldata data) external onlyApprovedCaller(delegateUser) returns (bytes memory) {
        return delegateUser ? _userLocalDelegateCall(data) : _userLocalStandardCall(data);
    }

    function allocatingCall(bytes calldata data) external onlyApprovedCaller(true) {
        return _allocatingCall(data);
    }

    function verificationCall(bytes calldata data) external onlyApprovedCaller(delegateVerification) returns (bool) {
        return _verificationCall(data);
    }

    // View functions
    function stagingDelegated() external view returns (bool delegated) {
        delegated = delegateStaging;
    }

    function userDelegated() external view returns (bool delegated) {
        delegated = delegateUser;
    }

    function userLocal() external view returns (bool local) {
        local = localUser;
    }

    function userDelegatedLocal() external view returns (bool delegated, bool local) {
        delegated = delegateUser;
        local = localUser;
    }

    function allocatingDelegated() external view returns (bool delegated) {
        delegated = delegateAllocating;
    }

    function verificationDelegated() external view returns (bool delegated) {
        delegated = delegateVerification;
    }

    function requireSequencedNonces() external view returns (bool isSequenced) {
        isSequenced = sequenced;
    }

    function getProtocolCall() external view returns (ProtocolCall memory protocolCall) {
        protocolCall = ProtocolCall({
            to: address(this),
            callConfig: CallBits.encodeCallConfig(
                sequenced,
                requireStaging,
                delegateStaging,
                localUser,
                delegateUser,
                delegateAllocating,
                requireVerification,
                delegateVerification,
                recycledStorage
                )
        });
    }

    function _getCallConfig() internal view returns (bool, bool, bool, bool, bool, bool, bool, bool, bool) {
        return (
            sequenced,
            requireStaging,
            delegateStaging,
            localUser,
            delegateUser,
            delegateAllocating,
            requireVerification,
            delegateVerification,
            recycledStorage
        );
    }

    function getCallConfig() external view returns (bool, bool, bool, bool, bool, bool, bool, bool, bool) {
        return _getCallConfig();
    }

    function getProtocolSignatory() external view returns (address governanceAddress) {
        governanceAddress = governance;
    }
}
