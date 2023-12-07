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
import { DAppOperation } from "../src/contracts/types/DAppApprovalTypes.sol";

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

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        // Deploy
        vm.startPrank(governanceEOA);

        controller = new DummyController(address(escrow), WETH_ADDRESS);
        atlasVerification.initializeGovernance(address(controller));
        atlasVerification.integrateDApp(address(controller));

        txBuilder = new TxBuilder({
            controller: address(controller),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });

        vm.stopPrank();

        arb = new ArbitrageTest();
        arb.setUpArbitragePools(chain.weth, chain.dai, 50e18, 100_000e18, address(arb.v2Router()), address(arb.s2Router()));

    }

    function testFlashLoanArbitrage() public {
        // Pools should already be setup for arbitrage. First try arbitraging without paying eth back to pool

        // Arbitrage is fulfilled by swapping WETH for DAI on Uniswap, then DAI for WETH on Sushiswap
        (uint256 revenue, uint256 optimalAmountIn) =
            arb.ternarySearch(chain.weth, chain.dai, arb.v2Router(), arb.s2Router(), 1, 50e18, 0, 20);

        vm.startPrank(solverOneEOA);
        SimpleArbitrageSolver solver = new SimpleArbitrageSolver(WETH_ADDRESS, address(atlas));
        deal(WETH_ADDRESS, address(solver), 1e18); // 1 WETH to solver to pay bid
        atlas.deposit{ value: 1e18 }();
        vm.stopPrank();

        // Input params for Atlas.metacall() - will be populated below

        vm.startPrank(userEOA);
        address executionEnvironment = atlas.createExecutionEnvironment(txBuilder.control());
        console.log("executionEnvironment a", executionEnvironment);
        vm.stopPrank();
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        UserOperation memory userOp = txBuilder.buildUserOperation({
            from: userEOA, // NOTE: Would from ever not be user?
            to: address(controller),
            maxFeePerGas: tx.gasprice + 1, // TODO update
            value: 0,
            deadline: block.number + 2,
            data: new bytes(0)
        });

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        bytes memory solverOpData =
            abi.encodeWithSelector(SimpleArbitrageSolver.arbitrageNoPayback.selector, arb.v2Router(), arb.s2Router(), chain.dai, optimalAmountIn);
        solverOps[0] = txBuilder.buildSolverOperation({
            userOp: userOp,
            solverOpData: solverOpData,
            solverEOA: solverOneEOA,
            solverContract: address(solver),
            bidAmount: 1e18,
            value: optimalAmountIn
        });

        // Solver signs the solverOp
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Frontend creates dAppOp calldata after seeing rest of data
        DAppOperation memory dAppOp = txBuilder.buildDAppOperation(governanceEOA, userOp, solverOps);

        // Frontend signs the dAppOp payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // make the actual atlas call
        vm.startPrank(userEOA);
        atlas.metacall({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();

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

    fallback() external {}
}

contract SimpleArbitrageSolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) { }

    function arbitrageNoPayback() external payable {
        // Empty function, take the weth and not return anything - should fail
    }

    function arbitrageWithPayback(address routerA, address routerB, address tradeToken, uint256 amountIn) external payable {

    }
}