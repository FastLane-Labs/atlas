//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/LockTypes.sol";

interface ISafetyLocks {
    function handleDAppOperation(
        DAppConfig calldata dConfig,
        bytes memory preOpsData,
        bytes memory userReturnData
    ) external;

    function activeEnvironment() external view returns (address);

    function getLockState() external view returns (EscrowKey memory);

    function confirmSafetyCallback() external view returns (bool);
}
