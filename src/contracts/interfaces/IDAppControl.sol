//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/UserCallTypes.sol";
import "../types/SolverCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface IDAppControl {
    function validateUserOperation(UserCall calldata uCall) external view returns (bool);

    function preOpsCall(UserCall calldata uCall) external returns (bytes memory);

    function allocateValueCall(bytes calldata data) external;

    function preSolverCall(bytes calldata data) external returns (bool);

    function postSolverCall(bytes calldata data) external returns (bool);

    function postOpsCall(bytes calldata data) external returns (bytes memory);

    function getDAppConfig() external view returns (DAppConfig memory dConfig);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function getBidFormat(UserCall calldata uCall) external view returns (BidData[] memory);

    function getBidValue(SolverOperation calldata solverOp) external view returns (uint256);

    function getDAppSignatory() external view returns (address governanceAddress);

    function requireSequencedNonces() external view returns (bool isSequenced);

    function preOpsDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);
}
