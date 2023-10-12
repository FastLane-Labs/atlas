//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IEscrow {
    function donateToBundler(address surplusRecipient) external payable;
    function repayBorrowedEth(address borrower) external payable;
    function cumulativeDonations() external view returns (uint256);
    function deposit(address solverSigner) external payable returns (uint256 newBalance);
    function nextSolverNonce(address solverSigner) external view returns (uint256 nextNonce);
    function solverEscrowBalance(address solverSigner) external view returns (uint256 balance);
    function solverLastActiveBlock(address solverSigner) external view returns (uint256 lastBlock);
}
