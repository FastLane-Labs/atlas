//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IEscrow {
    function reconcile(
        address environment,
        address solverFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (uint256 owed);
    function contribute() external payable;
    function borrow(uint256 amount) external payable;
    function shortfall() external view returns (uint256);
    function solverLockData() external view returns (address currentSolver, bool calledBack, bool fulfilled);
}
