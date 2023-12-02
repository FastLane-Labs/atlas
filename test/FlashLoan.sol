// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";
import { BaseTest } from "./base/BaseTest.t.sol";
import { ArbitrageTest } from "./base/ArbitrageTest.t.sol";
import { SolverBase } from "../src/contracts/solver/SolverBase.sol";
import { DAppControl } from "../src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "../src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../src/contracts/types/SolverCallTypes.sol";

contract FlashLoanTest is BaseTest {
    DummyController public controller;
    TxBuilder public txBuilder;
    ArbitrageTest public arb;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
    Sig public sig;

    function setUp() public virtual override {
        BaseTest.setUp();

        controller = new DummyController(address(escrow), WETH_ADDRESS);
        txBuilder = new TxBuilder({
            controller: address(controller),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });

        arb = new ArbitrageTest();
        arb.setUpArbitragePools(chain.weth, chain.dai, 50e18, 100_000e18, address(arb.v2Router()), address(arb.s2Router()));

    }

    function testFlashLoanArbitrage() public {

    } 

}

contract DummyController is DAppControl {
    address immutable weth;
    constructor(address _escrow, address _weth) DAppControl(
        _escrow,
        msg.sender,
        CallConfig({
            sequenced: false,
            requirePreOps: false,
            trackPreOpsReturnData: false,
            trackUserReturnData: false,
            localUser: false,
            delegateUser: true,
            preSolver: false,
            postSolver: false,
            requirePostOps: false,
            zeroSolvers: false,
            reuseUserOp: false,
            userBundler: true,
            solverBundler: true,
            verifySolverBundlerCallChainHash: true,
            unknownBundler: true,
            forwardReturnData: false,
            requireFulfillment: true
        })
    ) {
        weth = _weth;
    }

    function _allocateValueCall(address, uint256, bytes calldata) internal override {}

    function getBidFormat(UserOperation calldata) public view override returns (address bidToken) {
        bidToken = weth;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}

contract SimpleArbitrageSolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) { }
}