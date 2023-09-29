//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface IAtlas {
    function metacall( // <- Entrypoint Function
        DAppConfig calldata dConfig, // supplied by frontend
        UserOperation calldata userOp, // set by user
        SolverOperation[] calldata solverOps, // supplied by FastLane via frontend integration
        DAppOperation calldata dAppOp // supplied by front end after it sees the other data
    ) external payable returns (bool auctionWon, uint256 accruedGasRebate, uint256 solverIndex);

    function createExecutionEnvironment(DAppConfig calldata dConfig) external returns (address environment);

    function withdrawERC20(address token, uint256 amount, DAppConfig memory dConfig) external;
    function withdrawEther(uint256 amount, DAppConfig memory dConfig) external;

    function getEscrowAddress() external view returns (address escrowAddress);

    function getExecutionEnvironment(UserOperation calldata userOp, address controller)
        external
        view
        returns (address executionEnvironment);

    function getExecutionEnvironment(address user, address dAppControl) external view returns (address executionEnvironment, uint32 callConfig, bool exists);

    function userDirectVerifyDApp(
        address userOpFrom,
        address userOpTo,
        uint256 solverOpsLength,
        DAppConfig calldata dConfig,
        DAppOperation calldata verification
    ) external returns (bool);

    function userDirectReleaseLock(address userOpFrom, bytes32 key, DAppConfig calldata dConfig) external;

    function getDAppOperationPayload(DAppOperation memory verification) external view returns (bytes32 payload);

    function getSolverPayload(SolverCall calldata sCall) external view returns (bytes32 payload);

    function getUserOperationPayload(UserOperation memory userOp) external view returns (bytes32 payload);

    function nextUserNonce(address user) external view returns (uint256 nextNonce);
}
