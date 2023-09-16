//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

contract FastLaneErrorsEvents {
    // NOTE: nonce is the executed nonce
    event SolverTxResult(
        address indexed solverTo,
        address indexed solverFrom,
        bool executed,
        bool success,
        uint256 nonce,
        uint256 result
    );

    event UserTxResult(address indexed user, uint256 valueReturned, uint256 gasRefunded);

    event MEVPaymentFailure(
        address indexed controller, uint16 callConfig, BidData[] winningBids
    );


    error SolverBidUnpaid();
    error SolverFailedCallback();
    error SolverMsgValueUnpaid();
    error SolverOperationReverted();
    error SolverEVMError();
    error AlteredUserHash();
    error AlteredControlHash();
    error InvalidSolverHash();
    error HashChainBroken();
    error IntentUnfulfilled();
    error PreSolverFailed();
    error PostSolverFailed();
}
