//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IThogLock } from "../interfaces/IThogLock.sol";
import { IHandler } from "../interfaces/IHandler.sol";

interface ISearcherEscrow {
    struct SearcherEscrow {
        uint128 total;
        uint128 escrowed;
        uint64 availableOn; // block.number when funds are available.  
        uint64 lastAccessed;
        uint32 nonce; // EOA nonce.
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
        IThogLock.Lock memory mLock
    ) external;

    function releaseEscrowThogLock(
        uint256 keyCode
    ) external returns (uint256 gasRebate);
}
