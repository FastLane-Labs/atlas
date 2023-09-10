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

    event UserTxResult(address indexed user, uint256 valueReturned, uint256 gasRefunded);

    event MEVPaymentFailure(
        address indexed protocolControl, uint32 callConfig, BidData[] winningBids
    );


    error SearcherBidUnpaid();
    error SearcherFailedCallback();
    error SearcherMsgValueUnpaid();
    error SearcherCallReverted();
    error SearcherEVMError();
    error AlteredUserHash();
    error AlteredControlHash();
    error InvalidSearcherHash();
    error HashChainBroken();
    error IntentUnfulfilled();
    error SearcherStagingFailed();
    error SearcherVerificationFailed();
}
