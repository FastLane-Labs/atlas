//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

interface ISafetyLocks {
    function handleVerification(
        DAppConfig calldata dConfig,
        bytes memory preOpsData,
        bytes memory userReturnData
    ) external;

    function activeEnvironment() external view returns (address);

    function getLockState() external view returns (EscrowKey memory);

    function solverSafetyCallback(address msgSender) external payable returns (bool isSafe);

    function confirmSafetyCallback() external view returns (bool);
}
