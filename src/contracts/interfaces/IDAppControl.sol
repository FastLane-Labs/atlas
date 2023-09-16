//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface IDAppControl {
    function validateUserOperation(UserCall calldata uCall) external view returns (bool);

    function preOpsCall(UserCall calldata uCall) external returns (bytes memory);

    function userLocalCall(bytes calldata data) external returns (bytes memory);

    function allocatingCall(bytes calldata data) external;

    function preSolverCall(bytes calldata data) external returns (bool);

    function postSolverCall(bytes calldata data) external returns (bool);

    function postOpsCall(bytes calldata data) external returns (bytes memory);

    function getDAppConfig() external view returns (DAppConfig memory dConfig);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function getPayeeData(bytes calldata data) external returns (PayeeData[] memory);

    function getBidFormat(UserCall calldata uCall) external view returns (BidData[] memory);

    function getBidValue(SolverOperation calldata solverOp) external view returns (uint256);

    function getDAppSignatory() external view returns (address governanceAddress);

    function requireSequencedNonces() external view returns (bool isSequenced);

    function preOpsDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function userLocal() external view returns (bool local);

    function userDelegatedLocal() external view returns (bool delegated, bool local);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);
}
