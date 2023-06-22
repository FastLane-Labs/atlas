//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    SearcherCall,
    StagingCall,
    BidData,
    PayeeData,
    UserCall,
    SearcherProof,
    SearcherEscrow
} from "../libraries/DataTypes.sol";

interface IEscrow {

    struct ValueTracker {
        uint128 starting;
        uint128 transferredIn;
        uint128 transferredOut;
        uint128 gasRebate;
    }

    function executeStagingCall(
        SearcherProof memory proof,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function executeUserCall(
        SearcherProof memory proof,
        uint16 callConfig,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData);

    function executeSearcherCall(
        SearcherProof memory proof,
        uint256 gasWaterMark,
        bool auctionAlreadyComplete,
        SearcherCall calldata searcherCall
    ) external payable returns (bool);

    function executePayments(
        uint256 protocolShare,
        BidData[] calldata winningBids,
        PayeeData[] calldata payeeData
    ) external;

    function executeUserRefund(
        UserCall calldata userCall,
        bool callSuccess
    ) external;
}
