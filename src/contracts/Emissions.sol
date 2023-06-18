//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

contract FastLaneErrorsEvents {

    event SearcherTxResult(
        address indexed sender, 
        address indexed searcherContractAddress,
        address indexed protocol,
        uint256 nonce,
        uint256 result,
        uint256 gasSpent,
        uint256 remainingBalance
    );

    event UserTxResult(
        address indexed sender,
        address indexed protocol,
        bool userSuccess,
        bool searcherSuccess,
        uint256 gasRefunded
    );
}