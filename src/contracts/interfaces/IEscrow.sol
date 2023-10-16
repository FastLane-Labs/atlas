//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IEscrow {
    function donateToBundler(address surplusRecipient) external payable;
    function repayBorrowedEth(address borrower) external payable;
    function cumulativeDonations() external view returns (uint256);
    function deposit() external payable returns (uint256 newUnlockedBalance, uint256 newBalance);
    function withdraw(uint256 amount) external returns (uint256 newUnlockedBalance, uint256 newBalance);
    function escrowBalance(uint256 amount) external returns (uint256 newLockedBalance);
    function unescrowBalance(uint256 amount) external returns (uint256 newLockedBalance);
    function depositAndEscrowBalance() external payable returns (uint256 newLockedBalance, uint256 newBalance);
    function unescrowBalanceAndWithdraw(uint256 amount)
        external
        returns (uint256 newLockedBalance, uint256 newBalance);
    function nextSolverNonce(address solverSigner) external view returns (uint256 nextNonce);
    function solverEscrowBalance(address solverSigner) external view returns (uint256 balance);
    function solverLastActiveBlock(address solverSigner) external view returns (uint256 lastBlock);
}
