# Chain Configuration System

## Overview

The chain configuration system provides a centralized location for all chain-specific deployment parameters, eliminating hardcoded values scattered across deployment scripts.

## Architecture

### ChainConfig Library (`src/contracts/libraries/ChainConfig.sol`)

A pure Solidity library that stores all chain-specific parameters:
- **Escrow Duration**: Number of blocks for escrow period
- **L2 Gas Calculator**: Address of L2 gas calculator (if needed)
- **Atlas Surcharge Rate**: Fee percentage for Atlas operations (in basis points)
- **Bundler Surcharge Rate**: Fee percentage for bundler operations (in basis points)

### Supported Chains

#### Mainnet Chains
| Chain | Chain ID | Escrow Duration | Block Time | L2 Gas Calculator |
|-------|----------|-----------------|------------|-------------------|
| Ethereum | 1 | 64 blocks | ~12s | Not required |
| Polygon | 137 | 64 blocks | ~2s | Not required |
| Optimism | 10 | 16 blocks | ~2s | Required (OP Stack) |
| Base | 8453 | 16 blocks | ~2s | Required (OP Stack) |
| Arbitrum | 42161 | 128 blocks | ~250ms | Required (Arbitrum) |
| Hyperliquid | 999 | 30 blocks | ~1s | Not required |
| Unichain | 130 | 30 blocks | ~1s | Required (OP Stack) |
| Berachain | 80094 | 15 blocks | ~5s | Not required |

#### Testnet Chains
| Chain | Chain ID | Escrow Duration | Block Time | L2 Gas Calculator |
|-------|----------|-----------------|------------|-------------------|
| Sepolia | 11155111 | 64 blocks | ~12s | Not required |
| Polygon Amoy | 80002 | 64 blocks | ~2s | Not required |
| OP Sepolia | 11155420 | 16 blocks | ~2s | Required (OP Stack) |
| Base Sepolia | 84532 | 16 blocks | ~2s | Required (OP Stack) |
| Arbitrum Sepolia | 421614 | 128 blocks | ~250ms | Required (Arbitrum) |
| Unichain Sepolia | 1301 | 30 blocks | ~1s | Required (OP Stack) |
| Berachain Bepolia | 80069 | 15 blocks | ~5s | Not required |

## Usage

### In Deployment Scripts

```solidity
import { ChainConfig } from "../src/contracts/libraries/ChainConfig.sol";

contract DeployAtlasScript is DeployBaseScript {
    function run() external {
        // Get chain-specific configuration
        ChainConfig.ChainParameters memory chainParams = ChainConfig.getChainParameters(block.chainid);
        
        // Use parameters in deployment
        atlas = new Atlas({
            escrowDuration: chainParams.escrowDuration,
            atlasSurchargeRate: chainParams.atlasSurchargeRate,
            l2GasCalculator: chainParams.l2GasCalculator,
            // ... other parameters
        });
    }
}
```

### Helper Functions

```solidity
// Get chain name
string memory chainName = ChainConfig.getChainName(block.chainid);

// Check if L2 gas calculator is required
bool requiresCalc = ChainConfig.requiresL2GasCalculator(block.chainid);

// Get surcharge rates
ChainConfig.ChainParameters memory params = ChainConfig.getChainParameters(block.chainid);
uint256 atlasSurcharge = params.atlasSurchargeRate;    // in basis points (1000 = 10%)
uint256 bundlerSurcharge = params.bundlerSurchargeRate; // in basis points
```

## Adding New Chains

To add support for a new chain:

1. Add the chain configuration in `ChainConfig.sol`:
```solidity
} else if (chainId == YOUR_CHAIN_ID) {
    return ChainParameters({
        escrowDuration: BLOCKS,  // Calculate based on block time
        l2GasCalculator: address(0), // Or specific address if needed
        atlasSurchargeRate: 1000,  // 10% default
        bundlerSurchargeRate: 1000, // 10% default
        name: "YOUR_CHAIN_NAME"
    });
}
```

2. Update `requiresL2GasCalculator()` if the chain needs a gas calculator:
```solidity
function requiresL2GasCalculator(uint256 chainId) internal pure returns (bool) {
    return chainId == 42161 || chainId == 421614 || // Arbitrum chains
           chainId == 10 || chainId == 11155420 ||    // Optimism chains
           chainId == 8453 || chainId == 84532 ||     // Base chains
           chainId == 130 || chainId == 1301 ||       // Unichain chains
           chainId == YOUR_CHAIN_ID; // Add your chain if needed
}
```

## Escrow Duration Calculation

Escrow duration is calculated to achieve approximately 30-35 seconds of real time:

- **Ethereum/Sepolia**: 64 blocks × 12s = ~768s (adjusted for network conditions)
- **Polygon/Amoy**: 64 blocks × 2s = ~128s (adjusted for faster finality)
- **OP Stack (Optimism/Base)**: 16 blocks × 2s = ~32s
- **Arbitrum**: 128 blocks × 250ms = ~32s
- **Hyperliquid/Unichain**: 30 blocks × 1s = ~30s
- **Berachain**: 15 blocks × 5s = ~75s (Cosmos-based consensus)

## L2 Gas Calculator

L2 Gas Calculator requirements by chain type:
- **OP Stack chains (Base, Optimism, Unichain)**: Require L2 gas calculator for proper gas accounting
  - **Automatic Deployment**: The Atlas deployment script automatically deploys an L2 gas calculator if one is required but not configured
  - **Manual Deployment** (optional): Can be deployed separately using `script/deploy-gas-calculator-op-stack.s.sol`
- **Arbitrum chains**: Require specialized Arbitrum gas calculator
  - **Automatic Deployment**: The Atlas deployment script automatically deploys an Arbitrum gas calculator if one is required but not configured
  - **Manual Deployment** (optional): Can be deployed separately using `script/deploy-gas-calculator-arbitrum.s.sol`
- **Other chains (Ethereum, Polygon, Hyperliquid, Berachain)**: Standard gas calculation, no L2 calculator needed

## Arbitrum Deployment

Arbitrum is now fully supported on the main branch with automatic L2 gas calculator deployment:

### Deployment Process
1. Arbitrum chains are automatically detected during deployment
2. An ArbitrumGasCalculator will be deployed if not already configured
3. The deployment follows the same pattern as other L2 chains
- `arbitrum/atlas-v1.1` - Legacy version (not recommended for new deployments)
- `arbitrum/atlas-v1.0` - Legacy version (not recommended for new deployments)

### Switching to Arbitrum Branch
```bash
# List available Arbitrum branches
git branch -r | grep arbitrum

# Checkout the desired Arbitrum branch
git checkout arbitrum/atlas-v1.6.1

# Deploy on Arbitrum
forge script script/deploy-atlas.s.sol --chain-id 42161 --broadcast
```

If you attempt to deploy on Arbitrum from the main branch, you'll receive an error directing you to use the appropriate Arbitrum branch.

## Migration from Hardcoded Values

Previous approach:
```solidity
// In deploy-atlas.s.sol
uint256 ESCROW_DURATION = 128; // Hardcoded
address L2_GAS_CALCULATOR = 0x870584...;  // Hardcoded

// In deploy-base.s.sol
function _getSurchargeRates() internal view returns (...) {
    if (chainId == 137) {
        atlasSurchargeRate = 500; // Hardcoded
    }
}
```

New approach:
```solidity
// All configuration in one place
ChainConfig.ChainParameters memory params = ChainConfig.getChainParameters(block.chainid);
// Use params.escrowDuration, params.l2GasCalculator, etc.
```

## Testing

Run the test script to verify configuration:
```bash
forge script script/test-chain-config.s.sol -vv
```

This will display all chain configurations and verify the values are correctly set.

## Benefits

1. **Single Source of Truth**: All chain parameters in one location
2. **Type Safety**: Compile-time checking prevents errors
3. **Easy Maintenance**: Add new chains or update parameters in one place
4. **Reduced Duplication**: No more hardcoded values across multiple scripts
5. **Better Documentation**: Clear overview of all chain configurations
6. **Testability**: Easy to verify all configurations