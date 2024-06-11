// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { DAppOperation, DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";
import "src/contracts/types/LockTypes.sol";

import { TestUtils } from "./base/TestUtils.sol";

import {
    SwapIntentDAppControl,
    SwapIntent,
    Condition
} from "src/contracts/examples/intents-example/SwapIntentDAppControl.sol";

import { SolverBase } from "src/contracts/solver/SolverBase.sol";

import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";

// TODO Check if this is tested in more contract-specific tests, then delete this if true.
contract AccountingTest is BaseTest {
    SwapIntentDAppControl public swapIntentControl;
    TxBuilder public txBuilder;
    Sig public sig;

    DAppConfig dConfig;
    UserOperation userOp;
    DAppOperation dAppOp;

    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();

        // Creating new gov address (SignatoryActive error if already registered with control)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        // Deploy new SwapIntent Control from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        swapIntentControl = new SwapIntentDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(swapIntentControl));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            _control: address(swapIntentControl),
            _atlas: address(atlas),
            _verification: address(atlasVerification)
        });
    }

    function testSolverBorrowRepaySuccessfully() public {
        // Solver deploys the RFQ solver contract (defined at bottom of this file)
        vm.startPrank(solverOneEOA);
        HonestRFQSolver honestSolver = new HonestRFQSolver(WETH_ADDRESS, address(atlas));
        vm.stopPrank();

        SolverOperation[] memory solverOps = _setupBorrowRepayTestUsingBasicSwapIntent(address(honestSolver));

        vm.startPrank(userEOA);
        atlas.metacall{ value: 0 }({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();

        // console.log("\nAFTER METACALL");
        // console.log("User WETH balance", WETH.balanceOf(userEOA));
        // console.log("User DAI balance", DAI.balanceOf(userEOA));
        // console.log("Solver WETH balance", WETH.balanceOf(address(honestSolver)));
        // console.log("Solver DAI balance", DAI.balanceOf(address(honestSolver)));
        // console.log("Solver ETH balance", address(honestSolver).balance);
        // console.log("Atlas ETH balance", address(atlas).balance);

        // console.log("SearcherEOA", solverOneEOA);
        // console.log("Searcher contract", address(honestSolver));
        // console.log("UserEOA", userEOA);
    }

    function testSolverBorrowWithoutRepayingReverts() public {
        // Solver deploys the RFQ solver contract (defined at bottom of this file)
        vm.startPrank(solverOneEOA);
        // TODO make evil solver
        HonestRFQSolver evilSolver = new HonestRFQSolver(WETH_ADDRESS, address(atlas));
        // atlas.deposit{value: gasCostCoverAmount}(solverOneEOA);
        vm.stopPrank();

        SolverOperation[] memory solverOps = _setupBorrowRepayTestUsingBasicSwapIntent(address(evilSolver));

        vm.startPrank(userEOA);
        atlas.metacall{ value: 0 }({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();
    }

    function _setupBorrowRepayTestUsingBasicSwapIntent(address rfqSolver)
        internal
        returns (SolverOperation[] memory solverOps)
    {
        uint256 userMsgValue = 2e18;
        uint256 solverMsgValue = 1e18;

        // NOTE: the solver also has to pay the gas cost
        uint256 atlasStartBalance = solverMsgValue * 35 / 10;

        deal(userEOA, userMsgValue);
        vm.prank(solverTwoEOA);
        atlas.deposit{ value: atlasStartBalance }(); // Solver borrows 1 ETH from Atlas balance

        // Swap 10 WETH for 20 DAI
        SwapIntent memory swapIntent = SwapIntent({
            tokenUserBuys: DAI_ADDRESS,
            amountUserBuys: 20e18,
            tokenUserSells: WETH_ADDRESS,
            amountUserSells: 10e18,
            auctionBaseCurrency: address(0),
            conditions: new Condition[](0)
        });

        // Give 20 DAI to RFQ solver contract
        deal(DAI_ADDRESS, rfqSolver, swapIntent.amountUserBuys);
        assertEq(DAI.balanceOf(rfqSolver), swapIntent.amountUserBuys, "Did not give enough DAI to solver");

        // TODO remove
        // Give solverMsgValue (1e18, reusing var for stacktoodeep) of ETH to solver as well
        // deal(address(rfqSolver), solverMsgValue);

        // Input params for Atlas.metacall() - will be populated below

        solverOps = new SolverOperation[](1);

        vm.startPrank(userEOA);
        address executionEnvironment = atlas.createExecutionEnvironment(txBuilder.control());
        vm.stopPrank();
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        // swap(SwapIntent calldata) selector = 0x98434997
        bytes memory userCallData = abi.encodeCall(SwapIntentDAppControl.swap, swapIntent);

        // Builds the metaTx and to parts of userCall, signature still to be set
        userOp = txBuilder.buildUserOperation({
            from: userEOA,
            to: address(swapIntentControl),
            maxFeePerGas: tx.gasprice + 1,
            value: 0,
            deadline: block.number + 2,
            data: userCallData
        });
        userOp.sessionKey = governanceEOA;

        // User signs the userCall
        // user doees NOT sign the userOp when they are bundling
        // (sig.v, sig.r, sig.s) = vm.sign(userPK, atlas.getUserOperationPayload(userOp));
        // userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Build solver calldata (function selector on solver contract and its params)
        bytes memory solverOpData =
            abi.encodeCall(HonestRFQSolver.fulfillRFQ, (swapIntent, executionEnvironment));

        vm.prank(address(solverOneEOA));
        atlas.bond(1 ether);

        // Builds the SolverCall
        solverOps[0] = txBuilder.buildSolverOperation({
            userOp: userOp,
            solverOpData: solverOpData,
            solverEOA: solverOneEOA,
            solverContract: rfqSolver,
            bidAmount: solverMsgValue,
            value: 0
        });

        solverOps[0].value = solverMsgValue;

        // Solver signs the solverCall
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Frontend creates dApp Operation calldata after seeing rest of data
        dAppOp = txBuilder.buildDAppOperation(governanceEOA, userOp, solverOps);

        // Frontend signs the dApp Operation payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Check user token balances before
        uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);
        uint256 userDaiBalanceBefore = DAI.balanceOf(userEOA);

        vm.prank(userEOA); // Burn all users WETH except 10 so logs are more readable
        WETH.transfer(address(1), userWethBalanceBefore - swapIntent.amountUserSells);
        userWethBalanceBefore = WETH.balanceOf(userEOA);

        assertTrue(userWethBalanceBefore >= swapIntent.amountUserSells, "Not enough starting WETH");

        console.log("\nBEFORE METACALL");
        console.log("User WETH balance", WETH.balanceOf(userEOA));
        console.log("User DAI balance", DAI.balanceOf(userEOA));
        console.log("Solver WETH balance", WETH.balanceOf(address(rfqSolver)));
        console.log("Solver DAI balance", DAI.balanceOf(address(rfqSolver)));
        console.log("Solver ETH balance", address(rfqSolver).balance);
        console.log("Atlas ETH balance", address(atlas).balance);
        console.log(""); // give space for internal logs

        vm.startPrank(userEOA);

        (bool simResult,,) = simulator.simUserOperation(userOp);
        assertFalse(simResult, "metasimUserOperationcall tested true a");

        WETH.approve(address(atlas), swapIntent.amountUserSells);

        vm.stopPrank();
    }
}

// This solver magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
contract HonestRFQSolver is SolverBase {
    address public immutable ATLAS;

    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) {
        ATLAS = atlas;
    }

    function fulfillRFQ(SwapIntent calldata swapIntent, address executionEnvironment) public payable virtual {
        console.log("solver balance", address(this).balance);
        require(
            ERC20(swapIntent.tokenUserSells).balanceOf(address(this)) >= swapIntent.amountUserSells,
            "Did not receive enough tokenIn"
        );
        require(
            ERC20(swapIntent.tokenUserBuys).balanceOf(address(this)) >= swapIntent.amountUserBuys,
            "Not enough tokenOut to fulfill"
        );
        ERC20(swapIntent.tokenUserBuys).transfer(executionEnvironment, swapIntent.amountUserBuys);
    }

    // This ensures a function can only be called through atlasSolverCall
    // which includes security checks to work safely with Atlas
    modifier onlySelf() {
        require(msg.sender == address(this), "Not called via atlasSolverCall");
        _;
    }

    fallback() external payable { }
    receive() external payable { }
}

contract EvilRFQSolver is HonestRFQSolver {
    address deployer;

    constructor(address weth, address atlas) HonestRFQSolver(weth, atlas) {
        deployer = msg.sender;
    }

    function fulfillRFQ(SwapIntent calldata swapIntent, address executionEnvironment) public payable override {
        HonestRFQSolver.fulfillRFQ(swapIntent, executionEnvironment);

        // EvilRFQSolver tries to steal ETH before repaying debt to Atlas
        // deployer.call{value: msg.value}("");
    }
}
