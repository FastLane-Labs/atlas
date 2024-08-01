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

    //      UserOpHash  TotalBidValue
    mapping(bytes32 => uint256) public S_aggCongestionBuyIn;

    //      User        Nonce
    mapping(address => uint256) public S_userNonces;

    // OK hear me out
    // 1. We have to rake some of the congestion buyins to maintain incentive compatibility (a low rep solver smurfing
    // as a user to collect
    // congestion fees from competing solvers by bidding extremely high and knowing they'll get 100% of it back)
    // 2. Oval charges 50% of all OEV and we're just charging 33% of *only* the congestion fees - not MEV - which means
    // we're practically saints.
    uint256 internal constant _CONGESTION_RAKE = 33_000;
    uint256 internal constant _CONGESTION_BASE = 100_000;

    uint256 public rake = 0;

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
