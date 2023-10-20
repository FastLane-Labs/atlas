//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IEscrow {
    function validateBalances() external view returns (bool valid);
    function reconcile(address environment, address searcherFrom, uint256 maxApprovedGasSpend) external payable returns (bool);
}
