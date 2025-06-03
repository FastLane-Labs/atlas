// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { ArbitrumGasCalculator } from "../src/contracts/gasCalculator/ArbitrumGasCalculator.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

// Tests for Arbitrum-specific factors related to Atlas:
// - Getting the correct L2 block number using ArbSys precompile via SafeBlockNumber lib
// - Calldata gas estimation using ArbGasInfo precompile via Arbitrum L2GasCalculator
contract ArbitrumTest is BaseTest {
    // Arbitrum precompile addresses
    address ARB_GAS_INFO = 0x000000000000000000000000000000000000006C;
    address ARB_SYS = 0x0000000000000000000000000000000000000064;

    // Precompile Return Values at FORK_BLOCK
    uint256 PER_L2_TX = 9879; // per L2 tx in ArbGas
    uint256 PER_L1_CALLDATA_BYTE = 70; // per L1 calldata byte in ArbGas
    uint256 PER_STORAGE_ALLOCATION = 20000; // per storage allocation in ArbGas

    ArbitrumGasCalculator arbGasCalculator;

    function setUp() public virtual override {
        // Fork Arbitrum One for tests
        FORK_RPC_STRING = "ARBITRUM_RPC_URL";
        FORK_BLOCK = 343_453_130;
        vm.createSelectFork(vm.envString(FORK_RPC_STRING), FORK_BLOCK);

        // After forking, deploy the Arbitrum L2GasCalculator, then continue with standard test setup
        vm.prank(deployer);
        arbGasCalculator = new ArbitrumGasCalculator();
        L2_GAS_CALCULATOR = address(arbGasCalculator);
        DEFAULT_ESCROW_DURATION = 128; // 32 seconds at 250ms block times on Arbitrum

        // Deploy Arbitrum precompile mocks to simulate Arbitrum without Foundry errors
        vm.etch(ARB_SYS, address(new MockArbSys(FORK_BLOCK)).code);
        vm.etch(ARB_GAS_INFO, address(new MockArbGasInfo(
            PER_L2_TX,
            PER_L1_CALLDATA_BYTE,
            PER_STORAGE_ALLOCATION
        )).code);

        // The rest of the standard test setup, after forking Arbitrum
        __createAndLabelAccounts();
        __deployAtlasContracts();
        __fundSolversAndDepositAtlETH();
    }

    function test_Arbitrum_envSetUpAndAtlasDeployedCorrectly() public {
        // Check the Arbitrum precompile addresses are set correctly
        assertEq(FORK_BLOCK, MockArbSys(ARB_SYS).arbBlockNumber(), "ArbSys.arbBlockNumber mismatch");
        (uint256 l2TxPrice, uint256 l1CalldataPrice, uint256 storagePrice) = MockArbGasInfo(ARB_GAS_INFO).getPricesInArbGas();
        assertEq(l2TxPrice, PER_L2_TX, "ArbGasInfo: L2 tx price incorrect");
        assertEq(l1CalldataPrice, PER_L1_CALLDATA_BYTE, "ArbGasInfo: L1 calldata price incorrect");
        assertEq(storagePrice, PER_STORAGE_ALLOCATION, "ArbGasInfo: Storage price incorrect");

        // L2GasCalculator parameters
        assertEq(address(arbGasCalculator.ARB_GAS_INFO()), ARB_GAS_INFO, "ArbGasInfo incorrect");

        // Atlas and AtlasVerification parameters
        assertEq(L2_GAS_CALCULATOR, atlas.L2_GAS_CALCULATOR(), "Atlas.L2_GAS_CALCULATOR incorrect");
        assertEq(L2_GAS_CALCULATOR, atlasVerification.L2_GAS_CALCULATOR(), "AtlasVerification.L2_GAS_CALCULATOR incorrect");
        assertEq(DEFAULT_ESCROW_DURATION, atlas.ESCROW_DURATION(), "Atlas.ESCROW_DURATION incorrect");
        assertEq(DEFAULT_ATLAS_SURCHARGE_RATE, atlas.getAtlasSurchargeRate(), "Atlas surcharge rate incorrect");
    }
}

// Mocks the ArbSys precompile for SafeBlockNumber lib tests
contract MockArbSys {
    uint256 public immutable BLOCK_NUM;
    constructor(uint256 blockNum) {
        BLOCK_NUM = blockNum;
    }
    function arbBlockNumber() external view returns (uint256) {
        return BLOCK_NUM;
    }
}

// Mocks the ArbGasInfo precompile for gas estimation tests
contract MockArbGasInfo {
    uint256 public immutable PER_L2_TX;
    uint256 public immutable PER_L1_CALLDATA_BYTE;
    uint256 public immutable PER_STORAGE_ALLOCATION;

    constructor(
        uint256 perL2Tx,
        uint256 perL1CalldataByte,
        uint256 perStorageAllocation
    ) {
        PER_L2_TX = perL2Tx;
        PER_L1_CALLDATA_BYTE = perL1CalldataByte;
        PER_STORAGE_ALLOCATION = perStorageAllocation;
    }

    /// @notice Get prices in ArbGas. Assumes the callers preferred validator, or the default if caller doesn't have a preferred one.
    /// @return (per L2 tx, per L1 calldata byte, per storage allocation)
    function getPricesInArbGas() external view returns (uint256, uint256, uint256) {
        return (PER_L2_TX, PER_L1_CALLDATA_BYTE, PER_STORAGE_ALLOCATION);
    }
}
