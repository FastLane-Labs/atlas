//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

interface IAtlas {
    function metacall(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        Verification calldata verification
    ) external payable;

    function createExecutionEnvironment(DAppConfig calldata dConfig) external returns (address environment);

    function testUserOperation(UserCall calldata uCall) external view returns (bool);
    function testUserOperation(UserOperation calldata userOp) external view returns (bool);

    function withdrawERC20(address token, uint256 amount, DAppConfig memory dConfig) external;
    function withdrawEther(uint256 amount, DAppConfig memory dConfig) external;

    function getEscrowAddress() external view returns (address escrowAddress);

    function getExecutionEnvironment(UserOperation calldata userOp, address controller)
        external
        view
        returns (address executionEnvironment);

    function userDirectVerifyDApp(
        address userOpFrom,
        address userOpTo,
        uint256 solverOpsLength,
        DAppConfig calldata dConfig,
        Verification calldata verification
    ) external returns (bool);

    function userDirectReleaseLock(address userOpFrom, bytes32 key, DAppConfig calldata dConfig) external;

    function getVerificationPayload(Verification memory verification) external view returns (bytes32 payload);

    function getSolverPayload(SolverCall calldata fCall) external view returns (bytes32 payload);

    function getUserOperationPayload(UserOperation memory userOp) external view returns (bytes32 payload);

    function nextUserNonce(address user) external view returns (uint256 nextNonce);
}
