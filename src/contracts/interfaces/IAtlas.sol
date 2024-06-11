//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/LockTypes.sol";

// TODO add all Atlas functions here

interface IAtlas {

    function solverCall(
        uint256 bidAmount,
        uint256 gasLimit,
        EscrowKey calldata key,
        SolverOperation calldata solverOp,
        bytes calldata dAppReturnData
    ) external payable returns (SolverTracker memory sTracker);

    function metacall(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata verification
    )
        external
        payable
        returns (bool auctionWon);

    function VERIFICATION() external view returns (address);

    function isUnlocked() external view returns (bool);
}
