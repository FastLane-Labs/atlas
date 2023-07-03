//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import { CallChainProof } from "../types/VerificationTypes.sol";

interface IExecutionEnvironment {

    function protoCall( 
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls, // supplied by FastLane via frontend integration
        bytes32[] calldata executionHashChain // calculated by msg.sender (Factory)
    ) external payable returns (bytes32);

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