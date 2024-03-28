//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

// TODO add all Atlas functions here

interface IAtlas {
    function metacall(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata verification
    )
        external
        payable
        returns (bool auctionWon);

    function VERIFICATION() external view returns (address);

    function lock() external view returns (address);
}
