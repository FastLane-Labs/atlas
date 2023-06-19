//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IThogLock {
    struct Lock {
        uint8 _alpha;
        uint8 _omega;
        address _caller;
        uint256 _lockCode;
    }

    enum BaseLock {
        Unlocked,
        Pending,
        Locked
    }
}