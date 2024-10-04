// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ArbitrumTest } from "test/arbitrum/ArbitrumTest.t.sol";

/// @title ArbSysMock
/// @notice a mocked version of the Arbitrum system contract, add additional methods as needed
contract ArbSysMock {
    uint256 private constant ARBITRUM_BLOCK_NUMBER = 260_145_837;

    /// @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
    /// @return block number as uint256
    function arbBlockNumber() external view returns (uint256) {
        return ARBITRUM_BLOCK_NUMBER;
    }
}
