//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../types/UserOperation.sol";
import "../types/SolverOperation.sol";
import "../types/ConfigTypes.sol";

interface IDAppControl {
    function preOpsDelegateCall(UserOperation calldata userOp) external payable returns (bytes memory);

    function preSolverDelegateCall(SolverOperation calldata solverOp, bytes calldata returnData) external payable;

    function postSolverDelegateCall(SolverOperation calldata solverOp, bytes calldata returnData) external payable;

    function postOpsDelegateCall(bool solved, bytes calldata data) external payable;

    function allocateValueDelegateCall(address bidToken, uint256 bidAmount, bytes calldata data) external;

    function getDAppConfig(UserOperation calldata userOp) external view returns (DAppConfig memory dConfig);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function getBidFormat(UserOperation calldata userOp) external view returns (address bidToken);

    function getBidValue(SolverOperation calldata solverOp) external view returns (uint256);

    function getDAppSignatory() external view returns (address governanceAddress);

    function requireSequentialUserNonces() external view returns (bool isSequential);

    function requireSequentialDAppNonces() external view returns (bool isSequential);

    function preOpsDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);

    function CALL_CONFIG() external view returns (uint32);
}
