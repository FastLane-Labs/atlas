//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface IExecutionEnvironment {

    function delegateStagingWrapper(
        ProtocolCall calldata protocolCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function callStagingWrapper(
        ProtocolCall calldata protocolCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function callUserWrapper(
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData);

    function delegateUserWrapper(
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData);

    function callVerificationWrapper(
        ProtocolCall calldata protocolCall,
        bytes memory stagingData, 
        bytes memory userReturnData
    ) external;

    function delegateVerificationWrapper(
        ProtocolCall calldata protocolCall,
        bytes memory stagingData, 
        bytes memory userReturnData
    ) external;
}