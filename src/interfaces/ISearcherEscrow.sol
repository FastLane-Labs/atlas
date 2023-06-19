//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IThogLock } from "../interfaces/IThogLock.sol";

import {
    SearcherCall,
    StagingCall
} from "../libraries/DataTypes.sol";

interface ISearcherEscrow is IThogLock {
    
    struct SearcherEscrow {
        uint128 total;
        uint128 escrowed;
        uint64 availableOn; // block.number when funds are available.  
        uint64 lastAccessed;
        uint32 nonce; // EOA nonce.
    }

    struct ValueTracker {
        uint128 starting;
        uint128 transferred;
    }

    function searcherSafetyLock(
        address searcherSender, // the searcherCall.metaTx.from
        address executionCaller // the address of the ExecutionEnvironment 
        // NOTE: the execution caller is the msg.sender to the searcher's contract
    ) external returns (bool isSafe);
    
    function verify(
        bytes32 userCallHash,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) external returns (uint256 result, uint256 gasLimit);

    function update(
        uint256 gasWaterMark,
        uint256 result,
        SearcherCall calldata searcherCall
    ) external;

    function setEscrowThogLock(
        address activeHandler,
        Lock memory mLock
    ) external;

    function releaseEscrowThogLock(
        uint256 handlerKeyCode,
        uint256 searcherCallCount
    ) external returns (uint256 gasRebate, uint256 valueReturn);

    function handleDelegateStaging(
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData);

    function handleDelegateVerification(
        StagingCall calldata stagingCall,
        bytes memory stagingData
    ) external;
}
