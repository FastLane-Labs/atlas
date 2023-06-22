//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

contract FastLaneErrorsEvents {

    // NOTE: nonce is the executed nonce
    event SearcherTxResult(
        address indexed searcherTo,
        address indexed searcherFrom,
        bool executed,
        bool success,
        uint256 nonce, 
        uint256 result
    );

    event UserTxResult(
        address indexed user,
        address indexed protocol,
        bool searcherSuccess,
        uint256 valueReturned,
        uint256 gasRefunded
    );
}