// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title ChainConfig
/// @notice Central configuration library for chain-specific deployment parameters
/// @dev Single source of truth for all chain-specific configurations
library ChainConfig {
    struct ChainParameters {
        uint256 escrowDuration;
        address l2GasCalculator;
        uint256 atlasSurchargeRate;
        uint256 bundlerSurchargeRate;
        string name;
    }

    /// @notice Get chain-specific parameters based on chain ID
    /// @param chainId The blockchain chain ID
    /// @return params The chain-specific parameters
    function getChainParameters(uint256 chainId) internal pure returns (ChainParameters memory params) {
        // Mainnet chains
        if (chainId == 1) {
            // Ethereum Mainnet
            return ChainParameters({
                escrowDuration: 10, // ~12 seconds * 10 blocks = 120 seconds
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "MAINNET"
            });
        } else if (chainId == 137) {
            // Polygon
            return ChainParameters({
                escrowDuration: 64, // ~2 seconds * 32 blocks
                l2GasCalculator: address(0),
                atlasSurchargeRate: 500, // 5%
                bundlerSurchargeRate: 2000, // 20%
                name: "POLYGON"
            });
        } else if (chainId == 56) {
            // BSC
            return ChainParameters({
                escrowDuration: 32, // ~3 seconds * 10 blocks
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "BSC"
            });
        } else if (chainId == 10) {
            // Optimism
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0), // Will be deployed and set
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "OP MAINNET"
            });
        } else if (chainId == 42_161) {
            // Arbitrum One
            return ChainParameters({
                escrowDuration: 128, // ~250ms * 128 blocks = 32 seconds
                l2GasCalculator: address(0), // Will be deployed and set
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "ARBITRUM"
            });
        } else if (chainId == 8453) {
            // Base
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0), // Will be deployed and set
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "BASE"
            });
        } else if (chainId == 999) {
            // Hyperliquid
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "HYPERLIQUID"
            });
        }
        // Testnet chains
        else if (chainId == 11_155_111) {
            // Sepolia
            return ChainParameters({
                escrowDuration: 10, // ~12 seconds * 10 blocks = 120 seconds
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "SEPOLIA"
            });
        } else if (chainId == 17_000) {
            // Holesky
            return ChainParameters({
                escrowDuration: 64,
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "HOLESKY"
            });
        } else if (chainId == 80_002) {
            // Polygon Amoy
            return ChainParameters({
                escrowDuration: 64,
                l2GasCalculator: address(0),
                atlasSurchargeRate: 500, // 5%
                bundlerSurchargeRate: 2000, // 20%
                name: "AMOY"
            });
        } else if (chainId == 97) {
            // BSC Testnet
            return ChainParameters({
                escrowDuration: 32,
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "BSC TESTNET"
            });
        } else if (chainId == 11_155_420) {
            // Optimism Sepolia
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0), // Will be deployed and set
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "OP SEPOLIA"
            });
        } else if (chainId == 421_614) {
            // Arbitrum Sepolia
            return ChainParameters({
                escrowDuration: 128, // ~250ms * 128 blocks = 32 seconds
                l2GasCalculator: address(0), // Will be deployed and set
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "ARBITRUM_SEPOLIA"
            });
        } else if (chainId == 84_532) {
            // Base Sepolia
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0), // Will be deployed and set
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "BASE SEPOLIA"
            });
        } else if (chainId == 80_094) {
            // Berachain
            return ChainParameters({
                escrowDuration: 15, // ~2 seconds * 15 blocks = 30 seconds
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "BERACHAIN"
            });
        } else if (chainId == 80_069) {
            // Berachain Bepolia
            return ChainParameters({
                escrowDuration: 15, // ~2 seconds * 15 blocks = 30 seconds
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "BERACHAIN BEPOLIA"
            });
        } else if (chainId == 130) {
            // Unichain
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0), // Will be deployed and set (OP Stack based)
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "UNICHAIN"
            });
        } else if (chainId == 1301) {
            // Unichain Sepolia
            return ChainParameters({
                escrowDuration: 30, // ~1 second * 30 blocks = 30 seconds
                l2GasCalculator: address(0), // Will be deployed and set (OP Stack based)
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "UNICHAIN SEPOLIA"
            });
        } else if (chainId == 31_337) {
            // Local/Hardhat
            return ChainParameters({
                escrowDuration: 64,
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "LOCAL"
            });
        } else {
            // Default configuration for unknown chains
            return ChainParameters({
                escrowDuration: 64,
                l2GasCalculator: address(0),
                atlasSurchargeRate: 1000, // 10%
                bundlerSurchargeRate: 1000, // 10%
                name: "UNKNOWN"
            });
        }
    }

    /// @notice Check if a chain requires an L2 gas calculator
    /// @param chainId The blockchain chain ID
    /// @return True if the chain requires an L2 gas calculator
    function requiresL2GasCalculator(uint256 chainId) internal pure returns (bool) {
        // L2 chains require gas calculator for proper gas accounting
        return chainId == 42_161 || chainId == 421_614 // Arbitrum chains
            || chainId == 10 || chainId == 11_155_420 // Optimism chains
            || chainId == 8453 || chainId == 84_532 // Base chains
            || chainId == 130 || chainId == 1301; // Unichain chains
    }

    /// @notice Get chain name by ID (for backwards compatibility)
    /// @param chainId The blockchain chain ID
    /// @return The chain name as a string
    function getChainName(uint256 chainId) internal pure returns (string memory) {
        // Special handling for Arbitrum chains
        if (chainId == 42_161) return "ARBITRUM";
        if (chainId == 421_614) return "ARBITRUM_SEPOLIA";

        ChainParameters memory params = getChainParameters(chainId);
        if (keccak256(bytes(params.name)) != keccak256(bytes("UNKNOWN"))) {
            return params.name;
        }
        revert(string.concat("Error: Chain ID not recognized: ", toString(chainId)));
    }

    /// @notice Helper to convert uint256 to string
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
