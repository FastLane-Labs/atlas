//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    SearcherCall,
    StagingCall,
    BidData,
    PayeeData,
    UserCall
} from "../libraries/DataTypes.sol";

interface ISearcherEscrow {
    
    struct SearcherEscrow {
        uint128 total;
        uint128 escrowed;
        uint64 availableOn; // block.number when funds are available.  
        uint64 lastAccessed;
        uint32 nonce; // EOA nonce.
    }

    struct ValueTracker {
        uint128 starting;
        uint128 transferredIn;
        uint128 transferredOut;
        uint128 gasRebate;
    }

    function executeSearcherCall(
        bytes32 targetHash,
        bytes32 userCallHash,
        uint256 gasWaterMark,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) external returns (bool);

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
