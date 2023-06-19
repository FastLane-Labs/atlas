//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IFactory } from "../interfaces/IFactory.sol";
import { IHandler } from "../interfaces/IHandler.sol";

contract FastLaneDataTypes is IHandler {

    uint256 constant public SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 constant public VALIDATION_GAS_LIMIT = 500_000;
    uint256 constant public GWEI = 1_000_000_000;
    uint256 constant public SEARCHER_GAS_BUFFER = 5; // out of 100

    bytes32 internal constant _TYPE_HASH =
        keccak256("SearcherMetaTx(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes32 userCallHash,uint256 maxFeePerGas,bytes32 bidsHash,bytes data)");

    uint256 constant internal _NO_REFUND = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) 
    );

    uint256 constant internal _CALLDATA_REFUND = (
        1 << uint256(SearcherOutcome.InsufficientEscrow) |
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.UserOutOfGas) 
    );

    uint256 constant internal _FULL_REFUND = (
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat)
    );

    uint256 constant internal _EXTERNAL_REFUND = (
        1 << uint256(SearcherOutcome.NotWinner)
    );

    uint256 constant internal _EXECUTION_REFUND = (
        1 << uint256(SearcherOutcome.CallReverted) |
        1 << uint256(SearcherOutcome.BidNotPaid) |
        1 << uint256(SearcherOutcome.Success)
    );

    uint256 constant internal _NO_NONCE_UPDATE = (
        1 << uint256(SearcherOutcome.InvalidSignature) |
        1 << uint256(SearcherOutcome.AlreadyExecuted) |
        1 << uint256(SearcherOutcome.InvalidNonceUnder)
    );

    uint256 constant internal _BLOCK_VALID_EXECUTION = (
        1 << uint256(SearcherOutcome.InvalidNonceOver) |
        1 << uint256(SearcherOutcome.PerBlockLimit) |
        1 << uint256(SearcherOutcome.InvalidFormat) |
        1 << uint256(SearcherOutcome.InvalidUserHash) |
        1 << uint256(SearcherOutcome.InvalidBidsHash) |
        1 << uint256(SearcherOutcome.GasPriceOverCap) |
        1 << uint256(SearcherOutcome.UserOutOfGas) |
        1 << uint256(SearcherOutcome.NotWinner)
    );
}
