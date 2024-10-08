// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract ArbGasInfoMock {
    function getPricesInWei() external pure returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        // Realistic values for testing
        return (224_423_613_120, 1_603_025_808, 200_000_000_000, 10_000_000, 0, 10_000_000);
    }

    function getPricesInArbGas() external pure returns (uint256, uint256, uint256) {
        // Realistic values for testing
        return (22_442, 160, 20_000);
    }

    function getL1BaseFeeEstimate() external pure returns (uint256) {
        return 100_189_113;
    }

    // Implement other functions from ArbGasInfo interface as needed, returning static values
}
