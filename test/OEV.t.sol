// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";

import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { DAppOperation, DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";

import { ChainlinkDAppControl } from "src/contracts/examples/oev-example/ChainlinkDAppControl.sol";
import { SolverBase } from "src/contracts/solver/SolverBase.sol";


contract SwapIntentTest is BaseTest {
    ChainlinkDAppControl public chainlinkDAppControl;
    TxBuilder public txBuilder;
    Sig public sig;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        // Deploy new SwapIntent Controller from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        chainlinkDAppControl = new ChainlinkDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(chainlinkDAppControl));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            controller: address(chainlinkDAppControl),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });
    }

    function testChainlinkOEV() public {

        // NOTES:
        // - The EE must be whitelisted to post answers to Wrapper and Base oracles

        // Inside Atlas.metacall:
        // 1. userOp - updates the oracle wrapper with new int256
        // 2. solverOps - capture OEV by liquidating things that use the oracle wrapper
        // 3. postOpsCall - update the base chainlink oracle with signed `transmit` data
        
    }
}

// This solver magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
contract AaveLiquidationOEVSolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) { }

    // This ensures a function can only be called through metaFlashCall
    // which includes security checks to work safely with Atlas
    modifier onlySelf() {
        require(msg.sender == address(this), "Not called via metaFlashCall");
        _;
    }

    fallback() external payable { }
    receive() external payable { }
}