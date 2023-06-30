//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";

import "../types/CallTypes.sol";

contract SearcherBase {

    address immutable private _owner;
    address immutable private _escrow;

    constructor(address atlasEscrow, address owner) {
        _owner = owner;
        _escrow = atlasEscrow;
    }

    function metaFlashCall(
        address sender, 
        bytes calldata searcherCalldata, 
        BidData[] calldata bids
    ) external payable safetyFirst(sender, bids) 
        returns (bool success, bytes memory data) 
    {
        (
            success, 
            data
        ) = address(this).call{
            value: msg.value
        }(searcherCalldata);

        require(success, "CALL UNSUCCESSFUL");
    }

    modifier safetyFirst(address sender, BidData[] calldata bids) {
        // Safety checks
        require(sender == _owner, "INVALID CALLER");
        uint256 msgValueOwed = msg.value;
        
        _;

        // Handle bid payment
        uint256 i;
        for (; i < bids.length;) {

            // Ether balance
            if (bids[i].token == address(0)) {
                SafeTransferLib.safeTransferETH(msg.sender, bids[i].bidAmount);

            // ERC20 balance
            } else {
                SafeTransferLib.safeTransfer(ERC20(bids[i].token), msg.sender, bids[i].bidAmount);
            }
            unchecked {++i;}
        }

        // NOTE: Because this is nested inside of an Atlas meta transaction, if someone is attempting
        // to innappropriately access your smart contract then THEY will have to pay for the gas...
        // so feel free to run the safety checks at the end of the call.
        // NOTE: The searcherSafetyCallback is mandatory - if it is not called then the searcher
        // transaction will revert.  It is payable and can be used to repay a msg.value loan from the
        // Atlas Escrow. 
        require(ISafetyLocks(_escrow).searcherSafetyCallback{
            value: msgValueOwed
        }(msg.sender), "INVALID SEQUENCE");
    }
}