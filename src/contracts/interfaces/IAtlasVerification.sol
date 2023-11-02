//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../types/SolverCallTypes.sol";
import "../types/EscrowTypes.sol";

interface IAtlasVerification {

    
    function verifySolverOp(SolverOperation calldata solverOp, EscrowAccountData memory solverEscrow, uint256 gasWaterMark, bool auctionAlreadyComplete)
        external
        view
        returns (uint256 result, uint256 gasLimit, EscrowAccountData memory);
}