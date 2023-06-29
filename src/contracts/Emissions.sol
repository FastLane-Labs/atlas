//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

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

    event MEVPaymentFailure(
        address indexed protocolControl,
        uint16 callConfig,
        BidData[] winningBids,
        PayeeData[] payeeData
    );

    string constant public SEARCHER_BID_UNPAID = "SearcherBidUnpaid";
    bytes32 constant internal _SEARCHER_BID_UNPAID = keccak256(abi.encodePacked(SEARCHER_BID_UNPAID));

    string constant public SEARCHER_FAILED_CALLBACK = "SearcherCallbackFailed";
    bytes32 constant internal _SEARCHER_FAILED_CALLBACK = keccak256(abi.encodePacked(SEARCHER_FAILED_CALLBACK));

    string constant public SEARCHER_MSG_VALUE_UNPAID = "SearcherMsgValueNotRepaid";
    bytes32 constant internal _SEARCHER_MSG_VALUE_UNPAID = keccak256(abi.encodePacked(SEARCHER_MSG_VALUE_UNPAID));

    string constant public SEARCHER_CALL_REVERTED = "SearcherCallReverted";
    bytes32 constant internal _SEARCHER_CALL_REVERTED = keccak256(abi.encodePacked(SEARCHER_CALL_REVERTED));

    string constant public ALTERED_USER_HASH = "AlteredUserCalldataHash";
    bytes32 constant internal _ALTERED_USER_HASH = keccak256(abi.encodePacked(ALTERED_USER_HASH));

    string constant public INVALID_SEARCHER_HASH = "InvalidSearcherCalldataHash";
    bytes32 constant internal _INVALID_SEARCHER_HASH = keccak256(abi.encodePacked(INVALID_SEARCHER_HASH));

    string constant public HASH_CHAIN_BROKEN = "CalldataHashChainMismatch";
    bytes32 constant internal _HASH_CHAIN_BROKEN = keccak256(abi.encodePacked(HASH_CHAIN_BROKEN));

    // string constant SEARCHER_ETHER_BID_UNPAID = "SearcherMsgValueNotRepaid";
    // bytes32 constant _SEARCHER_ETHER_BID_UNPAID = keccak256(abi.encodePacked(SEARCHER_ETHER_BID_UNPAID));

}