//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    SearcherProof,
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    StagingCall,
    BidData,
    PayeeData,
    PaymentData,
    UserCall,
    CallConfig
} from "../libraries/DataTypes.sol";

interface ICallExecution {

    function callStagingWrapper(
        SearcherProof memory proof,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external payable returns (bytes memory stagingData);

    function delegateStagingWrapper(
        SearcherProof memory proof,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function callUserWrapper(
        SearcherProof memory proof,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData);

    function delegateUserWrapper(
        SearcherProof memory proof,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData);

    function callVerificationWrapper(
        StagingCall calldata stagingCall,
        bytes memory stagingData, 
        bytes memory userReturnData
    ) external;

    function delegateVerificationWrapper(
        StagingCall calldata stagingCall,
        bytes memory stagingData, 
        bytes memory userReturnData
    ) external;

    function searcherMetaTryCatch(
        SearcherProof memory proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external returns (uint256 searcherValueTransfer);

    function disbursePayments(
        uint256 protocolShare,
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) external;

}