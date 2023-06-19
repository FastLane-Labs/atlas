//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IThogLock } from "../interfaces/IThogLock.sol";
import { ISearcherEscrow } from "../interfaces/ISearcherEscrow.sol";
import { IFactory } from "../interfaces/IFactory.sol";
import { IHandler } from "../interfaces/IHandler.sol";

import { FastLaneDataTypes } from "./DataTypes.sol";

// NOTE: This is just a scratch pad for me to explore over-the-top strategies 
// that almost certainly won't work. In no way should anyone expect this lock system  
// to work, be readable, or be worth treating seriously. Trying to make sense
// of it offers no reward, is futile, and may cause irreparable brain damage. 
// (If you're new to working with me, remember that anything w/ the Thog prefix
// is just to test outlandish ideas and must be removed before staging or merging
// into main)

contract ThogLock is FastLaneDataTypes, IThogLock {

    address immutable internal _escrowAddress;
    address immutable internal _factoryAddress;

    // basic lock
    BaseLock internal _baseLock;

    // storage lock data
    uint256 internal _keyCode; 
    Lock internal _sLock;

    // load execution environment data for each protocol
    mapping(address => IFactory.ProtocolData) internal _protocolData;

    constructor(
        address escrowAddress,
        address factoryAddress
    ) {
        _escrowAddress = escrowAddress;
        _factoryAddress = factoryAddress;
    }

    function _initThogLock(
        address _activeHandler,
        UserCall calldata userCall,
        SearcherCall[] calldata searcherCalls
    ) internal returns (uint256 lockCode) {
        // address(this) == _factoryAddress

        require(msg.sender == tx.origin, "ERR-T00 InvalidCaller");

        require(msg.sender == userCall.from, "ERR-T02 SenderNotUser");

        require(_baseLock == BaseLock.Unlocked, "ERR-T01 Locked");

        lockCode = uint256(keccak256(abi.encodePacked(userCall.data, msg.sender)));
        
        uint256 i;
        for (; i < searcherCalls.length;) {
            lockCode ^= uint256(keccak256(abi.encodePacked(searcherCalls[i].signature, searcherCalls[i].metaTx.from)));
            unchecked { ++i; }
        }

        Lock memory mLock = Lock({
            _alpha: 0,
            _omega: uint8(searcherCalls.length),
            _caller: msg.sender,
            _lockCode: lockCode
        });

        ISearcherEscrow(_escrowAddress).setEscrowThogLock(_activeHandler, mLock);
        
        _baseLock = BaseLock.Locked;

        // TODO: lock is assumed breakable at each stage by the delegatecall
        // the alpha = omega check at end, as well as the initial alpha=0 
        // count at beginning of searcher repayment calcs, are the focus. 
        // the XORing will be either removed if unnecessary or made more robust 
        // by having each stage's result in the escrow contract checked by the 
        // factory contract. 
    }

    function baseLockStatus() external view returns (BaseLock baseLock) {
        baseLock = _baseLock; 
    }

    function _turnKeySafe(
        SearcherCall calldata searcherCall
    ) internal {
        // TODO: Lots of room for gas optimization here

        Lock memory mLock = _sLock;
        uint256 keyCode = _keyCode;

        require(
            (
                mLock._alpha < mLock._omega && 
                mLock._lockCode != 0
            ), "ERR-T04 NotLocked"
        );

        if (mLock._alpha == 0) {
            require(keyCode == 0, "ERR-T08 PriorTampering");
        }

        require(mLock._alpha < mLock._omega, "ERR-T09 Tampering");

        // increment the key-turn counter
        ++mLock._alpha;

        // apply the signed searcher calldata to the keycode
        _keyCode ^= uint256(keccak256(abi.encodePacked(searcherCall.signature, searcherCall.metaTx.from)));

        // save mLock back to storage
        _sLock = mLock;
    }
}

library ThogLockLib {
    
    function turnKeyUnsafe(
        uint256 keyCode,
        IHandler.SearcherCall calldata searcherCall
    ) internal pure returns (uint256 updatedKeyCode) {
        updatedKeyCode = keyCode ^ uint256(keccak256(abi.encodePacked(searcherCall.signature, searcherCall.metaTx.from)));
    }

    function initThogUnlock(
        uint256 _keyCode,
        address _escrow
    ) internal returns (uint256 gasRebate) {
        // address(this) == _handlerAddress
        // checks handler's keyCode memory (hidden from delegatecall) against escrow's lock,
        // which then checks it against the factory's lock

        gasRebate = ISearcherEscrow(_escrow).releaseEscrowThogLock(_keyCode);
    }
}