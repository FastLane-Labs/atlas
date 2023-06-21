//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    StagingCall,
    UserCall,
    PayeeData,
    SearcherCall,
    CallConfig,
    SearcherOutcome,
    BidData,
    PaymentData
} from "../libraries/DataTypes.sol";

interface IExecutionEnvironment {

    function delegateStagingWrapper(
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function callStagingWrapper(
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external payable returns (bytes memory stagingData);

    function callUserWrapper(
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData);

    function delegateUserWrapper(
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
}