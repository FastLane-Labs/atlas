//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface IAtlas {
    function metacall(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata verification
    ) external payable returns (bool auctionWon);

    function createExecutionEnvironment(DAppConfig calldata dConfig) external returns (address environment);

    function withdrawERC20(address token, uint256 amount, DAppConfig memory dConfig) external;
    function withdrawEther(uint256 amount, DAppConfig memory dConfig) external;

    function getEscrowAddress() external view returns (address escrowAddress);

    function getExecutionEnvironment(UserOperation calldata userOp, address controller)
        external
        view
        returns (address executionEnvironment);

    function getExecutionEnvironment(address user, address dAppControl) external view returns (address executionEnvironment);

    function userDirectVerifyDApp(
        address userOpFrom,
        address userOpTo,
        uint256 solverOpsLength,
        DAppConfig calldata dConfig,
        DAppOperation calldata verification
    ) external returns (bool);

    function userDirectReleaseLock(address userOpFrom, bytes32 key, DAppConfig calldata dConfig) external;

    function getDAppOperationPayload(DAppOperation memory verification) external view returns (bytes32 payload);
    
    function getDAppApprovalPayload(DAppApproval memory dAppApproval) external view returns (bytes32 payload);

    function getSolverPayload(SolverCall calldata sCall) external view returns (bytes32 payload);

    function getUserOperationPayload(UserOperation memory userOp) external view returns (bytes32 payload);

    function getUserCallPayload(UserCall memory userCall) external view returns (bytes32 payload);

    function getNextNonce(address account) external view returns (uint256 nextNonce);

    function getDomainSeparator() external view returns (bytes32 domainSeparator);
}
