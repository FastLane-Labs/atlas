//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

string constant SEARCHER_BID_UNPAID = "SearcherBidUnpaid";
string constant SEARCHER_FAILED_CALLBACK = "SearcherCallbackFailed";
string constant SEARCHER_MSG_VALUE_UNPAID = "SearcherMsgValueNotRepaid";
string constant SEARCHER_CALL_REVERTED = "SearcherCallReverted";
string constant SEARCHER_EVM_ERROR = "SearcherEVMError";
string constant ALTERED_USER_HASH = "AlteredUserCalldataHash";
string constant INVALID_SEARCHER_HASH = "InvalidSearcherCalldataHash";
string constant HASH_CHAIN_BROKEN = "CalldataHashChainMismatch";

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

    event UserTxResult(address indexed user, uint256 valueReturned, uint256 gasRefunded);

    event MEVPaymentFailure(
        address indexed protocolControl, uint16 callConfig, BidData[] winningBids
    );

    bytes32 internal constant _SEARCHER_BID_UNPAID = keccak256(abi.encodePacked(SEARCHER_BID_UNPAID));
    bytes32 internal constant _SEARCHER_FAILED_CALLBACK = keccak256(abi.encodePacked(SEARCHER_FAILED_CALLBACK));
    bytes32 internal constant _SEARCHER_MSG_VALUE_UNPAID = keccak256(abi.encodePacked(SEARCHER_MSG_VALUE_UNPAID));
    bytes32 internal constant _SEARCHER_CALL_REVERTED = keccak256(abi.encodePacked(SEARCHER_CALL_REVERTED));
    bytes32 internal constant _SEARCHER_EVM_ERROR = keccak256(abi.encodePacked(SEARCHER_EVM_ERROR));
    bytes32 internal constant _ALTERED_USER_HASH = keccak256(abi.encodePacked(ALTERED_USER_HASH));
    bytes32 internal constant _INVALID_SEARCHER_HASH = keccak256(abi.encodePacked(INVALID_SEARCHER_HASH));
    bytes32 internal constant _HASH_CHAIN_BROKEN = keccak256(abi.encodePacked(HASH_CHAIN_BROKEN));

    // string constant SEARCHER_ETHER_BID_UNPAID = "SearcherMsgValueNotRepaid";
    // bytes32 constant _SEARCHER_ETHER_BID_UNPAID = keccak256(abi.encodePacked(SEARCHER_ETHER_BID_UNPAID));
}
