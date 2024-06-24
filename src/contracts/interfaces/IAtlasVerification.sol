//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/SolverCallTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/ValidCallsTypes.sol";

interface IAtlasVerification {
    function validateCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        uint256 msgValue,
        address msgSender,
        bool isSimulation
    )
        external
        returns (bytes32 userOpHash, ValidCallsResult);

    function verifySolverOp(
        SolverOperation calldata solverOp,
        bytes32 userOpHash,
        uint256 userMaxFeePerGas,
        address bundler
    )
        external
        view
        returns (uint256 result);

    function getUserOperationPayload(UserOperation memory userOp) external view returns (bytes32 payload);
    function getSolverPayload(SolverOperation calldata solverOp) external view returns (bytes32 payload);
    function getDAppOperationPayload(DAppOperation memory dAppOp) external view returns (bytes32 payload);

    function getUserNextNonce(address user, bool sequential) external view returns (uint256 nextNonce);
    function getDAppNextNonce(address dApp, bool sequential) external view returns (uint256 nextNonce);

    function initializeGovernance(address control) external;
    function addSignatory(address control, address signatory) external;
    function removeSignatory(address control, address signatory) external;
    function disableDApp(address dAppControl) external;
}
