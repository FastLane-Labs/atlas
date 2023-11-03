//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface IAtlas {
    function metacall(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata verification
    ) external payable returns (bool auctionWon);

    function withdrawERC20(address token, uint256 amount, DAppConfig memory dConfig) external;
    function withdrawEther(uint256 amount, DAppConfig memory dConfig) external;

    // TODO remove this and inside Atlas - escrow addr is Atlas addr
    function getEscrowAddress() external view returns (address escrowAddress);

    function userDirectVerifyDApp(
        address userOpFrom,
        address userOpTo,
        uint256 solverOpsLength,
        DAppConfig calldata dConfig,
        DAppOperation calldata verification
    ) external returns (bool);

    function userDirectReleaseLock(address userOpFrom, bytes32 key, DAppConfig calldata dConfig) external;
}
