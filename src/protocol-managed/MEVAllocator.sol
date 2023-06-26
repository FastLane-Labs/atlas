//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import {
    BidData,
    PayeeData,
    PaymentData
} from "../libraries/DataTypes.sol";

abstract contract MEVAllocator {

    // Virtual functions to be overridden by participating protocol governance 
    // (not FastLane) prior to deploying contract. Note that protocol governance
    // will "own" this contract but that it should be immutable.  

      /////////////////////////////////////////////////////////
     //                MEV ALLOCATION                       //
    /////////////////////////////////////////////////////////
    //
    // MEV Allocation: 
    // Data should be decoded as:
    //
    //      uint256 totalEtherReward,
    //      BidData[] memory bids,
    //      PayeeData[] memory payeeData
    //

    // _allocateDelegateCall
    // Details:
    //  allocate/delegate = 
    //      Inputs: MEV Profits (ERC20 balances) and payeeData sourced by protocol frontend 
    //      Function: Executing the function set by ProtocolControl / MEVAllocator
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // Protocol exposure: Trustless 
    // User exposure: Trustless 
    function _allocatingDelegateCall(
        bytes calldata data
    ) internal virtual;


    // _allocateStandardCall
    // Details:
    //  allocate/standard call = 
    //      Inputs: MEV Profits (ERC20 balances) and payeeData sourced by protocol frontend 
    //      Function: Executing the function set by ProtocolControl / MEVAllocator
    //      Container: Inside of the ProtocolControl contract
    //      Access: With storage access (read + write) to the ProtocolControl contract
    //
    // NOTE: Currently disallowed due to all MEV rewards being held inn ExecutionEnvironment and
    // because changing that could disrupt trustlessness. 
    // TODO: More research to find a way to do this trustlessly. 
    function _allocatingStandardCall(
        bytes calldata // data
    // ) internal virtual;
    ) internal pure {require(true == false, "ERR-MEVA01 AllocateStandardDisallowed");}
}

contract AllocationExample {

    function _exampleAllocateMEV(
        BidData[] memory bids,
        PayeeData[] memory payeeData
    ) internal {
        
        PaymentData memory pmtData;
        
        address tokenAddress;
        uint256 payment;
        uint256 bidAmount;
        uint256 remainder;

        uint256 i;
        uint256 k;        

        for (; i < bids.length;) {
            tokenAddress = bids[i].token;
            bidAmount = bids[i].bidAmount;
            remainder = bidAmount;

            for (; k < payeeData[i].payments.length;) {

                pmtData = payeeData[i].payments[k];
                
                payment = bidAmount * pmtData.payeePercent;
                remainder -= payment;

                // Handle Ether
                if (tokenAddress == address(0)) {
                    SafeTransferLib.safeTransferETH(pmtData.payee, payment);

                // Handle ERC20
                } else {
                    SafeTransferLib.safeTransfer(ERC20(tokenAddress), pmtData.payee, payment);
                }
                
                unchecked{ ++k;}
            }

            unchecked{ ++i;}
        }
    }
}