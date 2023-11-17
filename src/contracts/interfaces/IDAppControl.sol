//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "../types/UserCallTypes.sol";
import "../types/SolverCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface IDAppControl {
    function preOpsCall(UserOperation calldata userOp) external payable returns (bytes memory);

    function preSolverCall(bytes calldata data) external payable returns (bool);

    function postSolverCall(bytes calldata data) external payable returns (bool);

    function postOpsCall(bytes calldata data) external payable returns (bytes memory);

    function allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) external;

    function getDAppConfig(UserOperation calldata userOp) external view returns (DAppConfig memory dConfig);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function getBidFormat(UserOperation calldata userOp) external view returns (address bidToken);

    function getBidValue(SolverOperation calldata solverOp) external view returns (uint256);

    function getDAppSignatory() external view returns (address governanceAddress);

    function requireSequencedNonces() external view returns (bool isSequenced);

    function preOpsDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);

    function callConfig() external view returns (uint32);
}
