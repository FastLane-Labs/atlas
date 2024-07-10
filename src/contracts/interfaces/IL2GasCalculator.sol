//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IL2GasCalculator {
    /// @notice Calculate the cost of calldata in ETH on a L2 with a different fee structure than mainnet
    function getCalldataCost(uint256 length) external view returns (uint256 calldataCostETH);
}
