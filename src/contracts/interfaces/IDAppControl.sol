//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../types/UserOperation.sol";
import "../types/SolverOperation.sol";
import "../types/ConfigTypes.sol";

interface IDAppControl {
    function preOpsCall(UserOperation calldata userOp) external payable returns (bytes memory);

    function preSolverCall(SolverOperation calldata solverOp, bytes calldata returnData) external payable;

    function postSolverCall(SolverOperation calldata solverOp, bytes calldata returnData) external payable;

    function allocateValueCall(bool solved, address bidToken, uint256 bidAmount, bytes calldata data) external;

    function getDAppConfig(UserOperation calldata userOp) external view returns (DAppConfig memory dConfig);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function CALL_CONFIG() external view returns (uint32);

    function getSolverGasLimit() external view returns (uint32);

    function getDAppGasLimit() external view returns (uint32);

    function getBundlerSurchargeRate() external view returns (uint24);

    function getBidFormat(UserOperation calldata userOp) external view returns (address bidToken);

    function getBidValue(SolverOperation calldata solverOp) external view returns (uint256);

    function getDAppSignatory() external view returns (address governanceAddress);

    function requireSequentialUserNonces() external view returns (bool isSequential);

    function requireSequentialDAppNonces() external view returns (bool isSequential);

    function userDelegated() external view returns (bool delegated);

    function transferGovernance(address newGovernance) external;

    function acceptGovernance() external;
}
