//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/SolverCallTypes.sol";
import "../types/EscrowTypes.sol";

interface IAtlasVerification {
    function verifyUser(DAppConfig memory dConfig, UserOperation calldata userOp)
        external
        returns (bool);

    function verifyDApp(DAppConfig memory dConfig, DAppOperation calldata dAppOp)
        external
        returns (bool);

    function verifySolverOp(SolverOperation calldata solverOp, EscrowAccountData memory solverEscrow, uint256 gasWaterMark, bool auctionAlreadyComplete)
        external
        view
        returns (uint256 result, uint256 gasLimit, EscrowAccountData memory);
}