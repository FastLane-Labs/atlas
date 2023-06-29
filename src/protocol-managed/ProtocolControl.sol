//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";

import { CallBits } from "../libraries/CallBits.sol";

import { GovernanceControl } from "./GovernanceControl.sol";
import { MEVAllocator } from "./MEVAllocator.sol";

import "../types/CallTypes.sol";

abstract contract ProtocolControl is MEVAllocator, GovernanceControl {


    address public immutable atlas;
    address public immutable governance;
    
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

        sequenced = shouldRequireSequencedNonces;

        // Disallow delegatecall when recycled storage is used
        if(allowRecycledStorage) {
            require(
                (
                    (!shouldDelegateStaging) &&
                    (!shouldDelegateUser) &&
                    (!shouldDelegateVerification)
                ),
                "ERR-GC01 DelegatingWithRecyled"
            );
        }

        if (shouldDelegateStaging) {
            require(shouldRequireStaging, "ERR-GC04 InvalidStaging");
        }

        if (shouldDelegateVerification) {
            require(shouldRequireVerification, "ERR-GC05 InvalidVerification");
        }

        // NOTE: At this time, MEV Allocation payments are required to be delegatecalled.
        // By the time the MEV Payments are paid, both the user and the searchers will
        // no longer be executing any transactions, and all MEV rewards will be
        // held in the ExecutionEnvironment 
        require(shouldDelegateAllocating, "ERR-GC02 NotDelegateAllocating");

        if (shouldDelegateUser) {
            require(shouldExecuteUserLocally, "ERR-GC03 SelfDelegating");
            // TODO: Consider allowing
        }

        atlas = escrowAddress;
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
    modifier onlyApprovedCaller() {
        require(
            msg.sender != address(0) &&
            msg.sender == ISafetyLocks(atlas).approvedCaller(),
            "InvalidCaller"
        );
        _;
    }

    function stageCall(
        bytes calldata data
    ) external onlyApprovedCaller returns (bytes memory) {
        return delegateStaging ? _stageDelegateCall(data) : _stageStaticCall(data);
    }

    function userLocalCall(
        bytes calldata data
    ) external onlyApprovedCaller returns (bytes memory) {
        return delegateUser ? _userLocalDelegateCall(data) : _userLocalStandardCall(data);
    }

    function allocatingCall(
        bytes calldata data
    ) external onlyApprovedCaller {
        return _allocatingDelegateCall(data);
    }

    function verificationCall(
        bytes calldata data
    ) external onlyApprovedCaller returns (bool) {
        return delegateVerification ? _verificationDelegateCall(data) : _verificationStaticCall(data);
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

     function _getCallConfig() internal view returns (
        bool, bool, bool, bool, bool, bool, bool, bool, bool
    ) {
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

    function getCallConfig() external view returns (
        bool, bool, bool, bool, bool, bool, bool, bool, bool
    ) {
        return _getCallConfig();
    }

    function getProtocolSignatory() external view returns (
        address governanceAddress
    ) {
        governanceAddress = governance;
    }
}