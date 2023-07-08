//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface ISearcherContract {
    function metaFlashCall(address sender, bytes calldata searcherCalldata, BidData[] calldata bids)
        external
        payable
        returns (bool, bytes memory);
}
