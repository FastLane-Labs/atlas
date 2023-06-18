//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { FastLaneDataTypes } from "./DataTypes.sol";
//import { FastLaneEscrow } from "./searcherEscrow.sol";

interface IFactory {
    function prepOuterLock(uint256 keyCode) external;
}

// NOTE: This is just a scratch pad for me to explore over-the-top strategies 
// that almost certainly won't work. In no way should anyone expect this lock system  
// to work, be readable, or be worth treating seriously. Trying to make sense
// of it offers no reward, is futile, and may cause irreparable brain damage. 
// (If you're new to working with me, remember that anything w/ the Thog prefix
// is just to test outlandish ideas and must be removed before staging or merging
// into main)

contract ThogLock is FastLaneDataTypes {

    struct Lock {
        uint8 _alpha;
        uint8 _omega;
        uint8 _epsilon;
        uint32 _nonce;
        address _caller;
        address _escrow;
        address _handler;
        uint256 _lockCode;
        uint256 _keyCode;
    }

    enum BaseLock {
        Unlocked,
        Pending,
        Locked
    }

    address immutable private _escrowAddress;
    address immutable private _factoryAddress;

    // basic lock
    BaseLock private _baseLock;

    // storage lock
    Lock private _sLock;

    // load execution environment data for each protocol
    mapping(address => ProtocolData) internal _protocolData;

    constructor(
        address escrowAddress,
        address factoryAddress
    ) {
        _escrowAddress = escrowAddress;
        _factoryAddress = factoryAddress;
    }

    function _thogLock(
        uint32 protocolNonce,
        address handlerAddress,
        SearcherCall[] calldata searcherCalls
    ) internal returns (Lock memory mLock) {
        // address(this) == _factoryAddress

        require(msg.sender == tx.origin, "ERR-T00 InvalidCaller");

        require(_baseLock == BaseLock.Unlocked, "ERR-T01 Locked");
        
        _baseLock = BaseLock.Locked;

        uint256 target;
        uint256 i;
        for (; i < searcherCalls.length;) {
            target ^= uint256(keccak256(searcherCalls[i].signature));
            unchecked {++i;}
        }

        mLock = Lock({
            _alpha: 0,
            _omega: uint8(searcherCalls.length),
            _epsilon: uint8(searcherCalls.length),
            _nonce: protocolNonce,
            _caller: msg.sender,
            _escrow: _escrowAddress,
            _handler: handlerAddress,
            _lockCode: target,
            _keyCode: 0
        });

        // this XOR is removed rapidly by the other contracts
        // to cross-verify their calldata at *start*. 
        mLock._lockCode ^= uint256(keccak256(abi.encodePacked(msg.sender)));

    }

    function baseLockStatus() external view returns (BaseLock baseLock) {
        baseLock = _baseLock; 
    }

    function _baseLockStatus() internal view returns (BaseLock baseLock) {
        baseLock = _baseLock; 
    }

    function _turnKeyUnsafe(
        Lock memory mLock,
        SearcherCall calldata searcherCall
    ) internal pure returns (Lock memory) {

        require(
            (
                mLock._alpha < mLock._epsilon && 
                mLock._omega > 0 &&
                mLock._lockCode != 0
            ), "ERR-T04 NotLocked"
        );

        // increment the things
        ++mLock._alpha;
        --mLock._omega;

        require(mLock._alpha + mLock._omega == mLock._epsilon, "ERR-T05 WrongSum");

        mLock._keyCode ^= uint256(keccak256(searcherCall.signature));
        mLock._lockCode ^= uint256(keccak256(searcherCall.signature));

        return mLock;
    }

    function _turnKeySafe(
        SearcherCall calldata searcherCall
    ) internal {
        // TODO: Lots of room for gas optimization here

        Lock memory mLock = _sLock;

        require(
            (
                mLock._alpha < mLock._epsilon && 
                mLock._omega > 0 &&
                mLock._lockCode != 0
            ), "ERR-T04 NotLocked"
        );

        if (mLock._alpha == 0) {
            mLock._lockCode ^= uint256(keccak256(abi.encodePacked(mLock._caller)));
        }

        // increment the things
        ++mLock._alpha;
        --mLock._omega;

        require(mLock._alpha + mLock._omega == mLock._epsilon, "ERR-T05 WrongSum");

        mLock._keyCode ^= uint256(keccak256(searcherCall.signature));
        mLock._lockCode ^= uint256(keccak256(searcherCall.signature));

        _sLock = mLock;
    }

    function releaseInnerLock(uint256 lockCode) external returns (Lock memory mLock) {
        // address(this) == escrowAddress

        mLock = _sLock;

        require(msg.sender == mLock._handler, "ERR-T03 InvalidCaller");

        require(
            (
                mLock._alpha == mLock._epsilon && 
                mLock._omega == 0 &&
                mLock._lockCode == 0
            ), "ERR-T04 MissingKeys"
        );

        require(lockCode == mLock._keyCode);

        _baseLock = BaseLock.Unlocked;

        IFactory(_factoryAddress).prepOuterLock(mLock._keyCode);

        delete _sLock;
    }


    function _unlock(Lock memory alphaLock) internal {
        // address(this) == _handlerAddress
        // checks protoCall's memory lock (hidden from delegatecall) against escrow's lock

        Lock memory omegaLock = ThogLock(alphaLock._escrow).releaseInnerLock(alphaLock._lockCode);

        require(alphaLock._omega == omegaLock._alpha, "ERR-T05 CountMismatch1");
        require(omegaLock._omega == 0, "ERR-T06 CountMismatch2");
        require(alphaLock._lockCode == omegaLock._keyCode, "ERR-T07 UnlockingFailure1");
        require(omegaLock._lockCode == 0, "ERR-T08 UnlockingFailure2");
    }

    
    
    function _thogUnlock(uint256 safetyLock, uint256 safetyCount) internal {
        // address(this) == _factoryAddress
        
        Lock memory lock = _sLock;

        require(lock._alpha == lock._omega, "ERR-T10 CountMismatch3");
        require(lock._omega == safetyCount, "ERR-T11 CountMismatch3");
        require(lock._lockCode == lock._keyCode, "ERR-T08 UnlockingFailure3");
        require(lock._keyCode == safetyLock, "ERR-T09 UnlockingFailure4");

        _baseLock = BaseLock.Unlocked;
    }


}