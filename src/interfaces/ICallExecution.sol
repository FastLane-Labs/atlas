//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    CallChainProof,
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    ProtocolCall,
    BidData,
    PayeeData,
    PaymentData,
    UserCall,
    CallConfig
} from "../libraries/DataTypes.sol";

interface ICallExecution {

    function stagingWrapper(
        CallChainProof memory proof,
        address protocolControl,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function userWrapper(
        CallChainProof memory proof,
        address protocolControl,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData);

    function verificationWrapper(
        CallChainProof memory proof,
        address protocolControl,
        bytes memory stagingReturnData, 
        bytes memory userReturnData
    ) external;

    function searcherMetaTryCatch(
        CallChainProof memory proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external;

    function allocateRewards(
        address protocolControl,
        BidData[] memory bids, // Converted to memory
        PayeeData[] calldata payeeData
    ) external;

}