//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

interface ISearcherContract {
    function fastLaneCall(address, uint256, bytes calldata) external payable returns (bool, bytes memory);
}

/// @notice contract call set by front end to prepare state for user's call (IE token transfers to address(this))
/// @param to address to call
/// @param stagingSelector func selector to call
/// @dev This is set by the front end!
/// @dev The stagingSelector's argument types must match the user's call's argument types to properly stage the meta tx.
struct StagingCall { 
    address to;
    bytes4 stagingSelector;
    bytes4 verificationSelector;
}

struct UserCall {
    address to;
    bytes data;
}

struct SearcherCall {
    address searcherContract;
    bytes searcherCalldata;
    BidData[] bids;
}

struct BidData {
    address token;
    uint256 bidAmount;
}

/// @notice protocol payee Data Struct
/// @param token token address (ERC20) being paid
struct PayeeData {
    address token;
    PaymentData[] payments;

}

/// @param payee address to pay
/// @param payeePercent percentage of bid to pay to payee (base 100)
/// @dev must sum to 100
struct PaymentData {
    address payee;
    uint256 payeePercent;
    bytes4 pmtSelector; // func selector (on payee contract) to call for custom pmt function. leave blank if payee receives funds via ERC20 transfer
}


contract FastLaneProtoHandler is ReentrancyGuard {

    uint256 constant internal SEARCHER_GAS_LIMIT = 1_000_000;

    uint256 internal PROTOCOL_SHARE = 5;

    function protoMetaCall(
        StagingCall calldata stagingCall,
        UserCall calldata userCall,
        PayeeData[] calldata payees,
        SearcherCall[] calldata searcherCalls
    ) external payable {

            // declare some variables
            bool callSuccess; // reuse memory variable
            bytes memory stagingData; // capture any pre-execution state variables the protocol may need
            bytes memory returnData; // capture any pre-execution state variables the protocol may need


            // Stage the execution environment for the user, if necessary
            if (stagingCall.stagingSelector != bytes4(0)) {
                (callSuccess, stagingData) = stagingCall.to.delegatecall(
                        bytes.concat(stagingCall.stagingSelector, userCall.data[4:])
                );
                require(callSuccess, "ERR-01 Staging");
            }

            (callSuccess, returnData) = userCall.to.call(userCall.data);
            require(callSuccess, "ERR-02 UserCall");

    }

}