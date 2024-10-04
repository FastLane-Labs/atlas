// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract ArbGasInfoMock {
    function getPricesInWei()
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        // Realistic values for testing
        return (224423613120, 1603025808, 200000000000, 10000000, 0, 10000000);
    }

    function getPricesInArbGas()
        external
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Realistic values for testing
        return (22442, 160, 20000);
    }

    function getL1BaseFeeEstimate() external pure returns (uint256) {
        return 100189113;
    }

    // Implement other functions from ArbGasInfo interface as needed, returning static values
}