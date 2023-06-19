//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IThogLock } from "../interfaces/IThogLock.sol";
import { IHandler } from "../interfaces/IHandler.sol";

//import "../contracts/DataTypes.sol";
//import { SearcherOutcome } from "../contracts/DataTypes.sol";

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
    
    function verify(
        bytes32 userCallHash,
        bool callSuccess,
        IHandler.SearcherCall calldata searcherCall
    ) external returns (uint256 result, uint256 gasLimit);

    function update(
        uint256 gasWaterMark,
        uint256 result,
        IHandler.SearcherCall calldata searcherCall
    ) external;

    function setEscrowThogLock(
        address activeHandler,
        Lock memory mLock
    ) external;

    function releaseEscrowThogLock(
        uint256 handlerKeyCode,
        uint256 searcherCallCount
    ) external returns (uint256 gasRebate, uint256 valueReturn);
}
