//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISafetyChecks } from "../interfaces/ISafetyChecks.sol";

import { GovernanceControl } from "./GovernanceControl.sol";
import { MEVAllocator } from "./MEVAllocator.sol";

import {
    BidData,
    PayeeData
} from "../libraries/DataTypes.sol";

abstract contract ProtocolControl is MEVAllocator, GovernanceControl {

    address public immutable fastLaneEscrow;
    
    bool public immutable delegateStaging;
    bool public immutable localUser;
    bool public immutable delegateUser;
    bool public immutable delegateAllocating;
    bool public immutable delegateVerification;
    bool public immutable recycledStorage;

    constructor(
        address escrowAddress,
        bool shouldDelegateStaging,
        bool shouldExecuteUserLocally,
        bool shouldDelegateUser,
        bool shouldDelegateAllocating,
        bool shouldDelegateVerification,
        bool allowRecycledStorage
        
    ) {

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

        // NOTE: At this time, MEV Allocation payments are required to be delegatecalled.
        // By the time the MEV Payments are paid, both the user and the searchers will
        // no longer be executing any transactions, and all MEV rewards will be
        // held in the ExecutionEnvironment 
        require(shouldDelegateAllocating, "ERR-GC02 NotDelegateAllocating");

        if (shouldDelegateUser) {
            require(shouldExecuteUserLocally, "ERR-GC03 SelfDelegating");
            // TODO: Consider allowing
        }

        fastLaneEscrow = escrowAddress;

        delegateStaging = shouldDelegateStaging;
        localUser = shouldExecuteUserLocally;
        delegateUser = shouldDelegateUser;
        delegateAllocating = shouldDelegateAllocating;
        delegateVerification = shouldDelegateVerification;
        recycledStorage = allowRecycledStorage;
    }

    // Safety and support functions and modifiers that make the relationship between protocol 
    // and FastLane's backend trustless.
    modifier onlyApprovedCaller() {
        require(
            msg.sender != address(0) &&
            msg.sender == ISafetyChecks(fastLaneEscrow).approvedCaller(),
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
}