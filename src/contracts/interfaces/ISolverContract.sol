//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface ISolverContract {
    function atlasSolverCall(address sender, BidData[] calldata bids, bytes calldata solverOpData)
        external
        payable
        returns (bool, bytes memory);
}
