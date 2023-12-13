//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Party } from "../types/EscrowTypes.sol";

interface IEscrow {
    function validateBalances() external view returns (bool valid);
    function reconcile(
        address environment,
        address solverFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (bool);
    function contribute() external payable;
    function borrow(uint256 amount) external payable;
    function shortfall() external view returns (uint256);
}
