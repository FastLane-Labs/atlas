//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IL2GasCalculator {
    function calculateL2GasCost(uint256 gas) external view returns (uint256 gasCostETH);
}