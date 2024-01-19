//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/SolverCallTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/ValidCallsTypes.sol";

interface IAtlasVerification {
    function validCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        uint256 msgValue,
        address msgSender,
        bool isSimulation
    )
        external
        returns (SolverOperation[] memory, ValidCallsResult);

    function verifySolverOp(
        SolverOperation calldata solverOp,
        EscrowAccountBalance memory solverEscrow,
        uint256 gasWaterMark,
        bool auctionAlreadyComplete
    )
        external
        view
        returns (uint256 result, uint256 gasLimit, EscrowAccountBalance memory);

    function getUserOperationPayload(UserOperation memory userOp) external view returns (bytes32 payload);
    function getSolverPayload(SolverOperation calldata solverOp) external view returns (bytes32 payload);
    function getDAppOperationPayload(DAppOperation memory dAppOp) external view returns (bytes32 payload);
    function getNextNonce(address account) external view returns (uint256 nextNonce);

    function initializeGovernance(address controller) external;
    function addSignatory(address controller, address signatory) external;
    function removeSignatory(address controller, address signatory) external;
    function disableDApp(address dAppControl) external;

    function initializeNonce(address account) external;
}
