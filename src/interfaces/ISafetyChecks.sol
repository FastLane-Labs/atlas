//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    StagingCall,
    UserCall
} from "../libraries/DataTypes.sol";

interface ISafetyChecks {
    struct EscrowKey {
        address approvedCaller;
        bool makingPayments;
        bool paymentsComplete;
        uint8 callIndex;
        uint8 callMax;
        uint64 lockState; // bitwise
    }

    enum BaseLock {
        Unlocked,
        Pending,
        Active,
        Untrusted,
        DelegatingCall
    }

    enum ExecutionPhase {
        Uninitialized,
        Staging,
        UserCall,
        SearcherCalls,
        HandlingPayments,
        UserRefund,
        Verification,
        Releasing
    }

    enum SearcherSafety {
        Unset,
        Requested,
        Verified
    }

    function handleStaging(
        bytes32 targetHash,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function handleUser(
        bytes32 targetHash,
        uint16 callConfig,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData);

    function handleVerification(
        StagingCall calldata stagingCall,
        bytes memory stagingData,
        bytes memory userReturnData
    ) external;

}