//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/DAppOperation.sol";
import "src/contracts/types/LockTypes.sol";

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

    function isUnlocked() external view returns (bool);

    function lock() external returns (address);

    function shortfall() external view returns (uint256);

    function contribute() external payable;

    function borrow(uint256 amount) external payable;

    function reconcile(uint256 maxApprovedGasSpend) external payable returns (uint256 owed);
}
