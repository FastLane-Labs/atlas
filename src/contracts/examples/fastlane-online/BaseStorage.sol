//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "src/contracts/types/SolverOperation.sol";

contract BaseStorage {

    address internal _userLock = address(1); // TODO: Convert to transient storage

    //   SolverOpHash   SolverOperation
    mapping(bytes32 => SolverOperation) public S_solverOpCache;

    //      UserOpHash  SolverOpHash[]
    mapping(bytes32 => bytes32[]) public S_solverOpHashes;

    //      SolverOpHash  BidValue
    mapping(bytes32 => uint256) public S_congestionBuyIn;

    //      User        Nonce
    mapping(address => uint256) public S_userNonces;


    //////////////////////////////////////////////
    /////            MODIFIERS              //////
    //////////////////////////////////////////////
    modifier withUserLock() {
        if (_userLock != address(1)) revert();
        _userLock = msg.sender;
        _;
        _userLock = address(1);
    }

    modifier onlyWhenUnlocked() {
        if (_userLock != address(1)) revert();
        _;
    }

}