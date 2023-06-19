//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IHandler } from "../interfaces/IHandler.sol";

interface ISearcherContract {

    function metaFlashCall(
        address sender, 
        bytes calldata searcherCalldata, 
        IHandler.BidData[] calldata bids
    ) external payable returns (bool, bytes memory);
}