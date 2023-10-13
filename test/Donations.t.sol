// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";
import {SolverOperation} from "../src/contracts/types/SolverCallTypes.sol";
import {UserOperation} from "../src/contracts/types/UserCallTypes.sol";
import {DAppOperation, DAppConfig} from "../src/contracts/types/DAppApprovalTypes.sol";

import {SwapIntentController, SwapIntent, Condition} from "../src/contracts/examples/intents-example/SwapIntent.sol";

import {SolverBase} from "../src/contracts/solver/SolverBase.sol";

contract DonationsTest is BaseTest {

    SwapIntentController public swapIntentController;
    TxBuilder public txBuilder;
    Sig public sig;

    DAppConfig dConfig;
    UserOperation userOp;
    DAppOperation dAppOp;

    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    // Swap 10 WETH for 20 DAI
    address tokenUserBuys = DAI_ADDRESS;
    uint256 amountUserBuys = 20e18;
    address tokenUserSells = WETH_ADDRESS;
    uint256 amountUserSells = 10e18;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller) 
        governancePK = 11112;
        governanceEOA = vm.addr(governancePK);

        // Deploy new SwapIntent Controller from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        swapIntentController = new SwapIntentController(address(escrow));        
        atlas.initializeGovernance(address(swapIntentController));
        atlas.integrateDApp(address(swapIntentController));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            controller: address(swapIntentController),
            escrowAddress: address(escrow),
            atlasAddress: address(atlas)
        });
    }

    function testSolverCanDonateToBundlerOncePerPhase() public {
        // Solver deploys the RFQ solver contract (defined at bottom of this file)
        vm.startPrank(solverOneEOA);
        SingleDonateRFQSolver solver = new SingleDonateRFQSolver(address(atlas));
        vm.stopPrank();

        SolverOperation[] memory solverOps = _setupBorrowRepayTestUsingBasicSwapIntent(address(solver));
        
        uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);
        uint256 userDaiBalanceBefore = DAI.balanceOf(userEOA);
        uint256 solverWethBalanceBefore = WETH.balanceOf(address(solver));
        uint256 solverDaiBalanceBefore = DAI.balanceOf(address(solver));

        assertEq(address(solver).balance, 0, "Solver has unexpected ETH");

        // Deal solver 1 ETH which should get donated and not affect DAI/WETH balances
        deal(address(solver), 1e18);

        vm.startPrank(userEOA);
        atlas.metacall{value: 0}({
            dConfig: dConfig,
            userOp: userOp,
            solverOps: solverOps,
            dAppOp: dAppOp
        });
        vm.stopPrank();

        assertEq(WETH.balanceOf(userEOA), userWethBalanceBefore - amountUserSells, "User did not pay WETH");
        assertEq(DAI.balanceOf(userEOA), userDaiBalanceBefore + amountUserBuys, "User did not receive DAI");
        assertEq(WETH.balanceOf(address(solver)), solverWethBalanceBefore + amountUserSells - 1e18, "Solver did not receive WETH");
        assertEq(DAI.balanceOf(address(solver)), solverDaiBalanceBefore - amountUserBuys, "Solver did not pay DAI");
    
        // Check solver recieved his donation surplus: 1 ETH > x > 0.9 ETH
        assertTrue(address(solver).balance > 0.9e18, "Solver received too little donation surplus");
        assertTrue(address(solver).balance < 1e18, "Solver received too much donation surplus");
    }
    function testSolverDonateToBundlerTwicePerPhaseReverts() public {
        // Solver deploys the RFQ solver contract (defined at bottom of this file)
        vm.startPrank(solverOneEOA);
        DoubleDonateRFQSolver solver = new DoubleDonateRFQSolver(address(atlas));
        vm.stopPrank();

        SolverOperation[] memory solverOps = _setupBorrowRepayTestUsingBasicSwapIntent(address(solver));

        // Deal solver 2 ETH which should get donated in 2x 1 ETH batches
        deal(address(solver), 2e18);

        vm.startPrank(userEOA);
        // Reverts internally with "ERR-EV014 NotFirstDonation"
        vm.expectRevert("ERR-F07 RevertToReuse");
        atlas.metacall{value: 0}({
            dConfig: dConfig,
            userOp: userOp,
            solverOps: solverOps,
            dAppOp: dAppOp
        });
        vm.stopPrank();
    }

    function _setupBorrowRepayTestUsingBasicSwapIntent(address rfqSolver) internal returns (SolverOperation[] memory solverOps){
       uint256 userMsgValue = 2e18;
        uint256 solverMsgValue = 1e18;
        uint256 atlasStartBalance = solverMsgValue * 12 / 10;

        deal(userEOA, userMsgValue);
        vm.prank(solverTwoEOA);
        atlas.deposit{value: atlasStartBalance}(solverTwoEOA); // Solver borrows 1 ETH from Atlas balance

        // Swap 10 WETH for 20 DAI
        SwapIntent memory swapIntent = SwapIntent({
            tokenUserBuys: tokenUserBuys,
            amountUserBuys: amountUserBuys,
            tokenUserSells: tokenUserSells,
            amountUserSells: amountUserSells,
            auctionBaseCurrency: address(0),
            solverMustReimburseGas: false,
            conditions: new Condition[](0)
        });

        // Give 20 DAI to RFQ solver contract
        deal(DAI_ADDRESS, rfqSolver, swapIntent.amountUserBuys);
        assertEq(DAI.balanceOf(rfqSolver), swapIntent.amountUserBuys, "Did not give enough DAI to solver");

        // Input params for Atlas.metacall() - will be populated below
        dConfig = txBuilder.getDAppConfig();
        solverOps = new SolverOperation[](1);

        vm.startPrank(userEOA);
        address executionEnvironment = atlas.createExecutionEnvironment(dConfig);
        vm.stopPrank();
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        // swap(SwapIntent calldata) selector = 0x98434997
        bytes memory userCallData = abi.encodeWithSelector(SwapIntentController.swap.selector, swapIntent);

        // Builds the metaTx and to parts of userCall, signature still to be set
        userOp = txBuilder.buildUserOperation({
            from: userEOA,
            to: address(swapIntentController),
            maxFeePerGas: tx.gasprice + 1,
            value: 0,
            deadline: block.number + 2,
            data: userCallData
        });

        // User signs the userCall
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlas.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Build solver calldata (function selector on solver contract and its params)
        bytes memory solverOpData = abi.encodeWithSelector(
            SingleDonateRFQSolver.fulfillRFQ.selector, 
            swapIntent,
            executionEnvironment
        );

        // Builds the SolverCall
        solverOps[0] = txBuilder.buildSolverOperation({
            userOp: userOp,
            dConfig: dConfig,
            solverOpData: solverOpData,
            solverEOA: solverOneEOA,
            solverContract: rfqSolver,
            bidAmount: solverMsgValue
        });

        solverOps[0].call.value = solverMsgValue;

        // Solver signs the solverCall
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlas.getSolverPayload(solverOps[0].call));
        solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Frontend creates dApp Operation calldata after seeing rest of data
        dAppOp = txBuilder.buildDAppOperation(governanceEOA, dConfig, userOp, solverOps);

        // Frontend signs the dApp Operation payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlas.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Check user token balances before
        uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);

        vm.prank(userEOA); // Burn all users WETH except 10 so logs are more readable
        WETH.transfer(address(1), userWethBalanceBefore - swapIntent.amountUserSells);
        userWethBalanceBefore = WETH.balanceOf(userEOA);

        assertTrue(userWethBalanceBefore >= swapIntent.amountUserSells, "Not enough starting WETH");

        vm.startPrank(userEOA);
        WETH.approve(address(atlas), swapIntent.amountUserSells);
        vm.stopPrank();
    }
}


// This solver magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
// NOTE: Solver 1 will attempt to donate 1 ETH, solver 2 will attempt to donate 1 ETH twice
contract SingleDonateRFQSolver is SolverBase {
    address public immutable ATLAS;
    constructor(address atlas) SolverBase(atlas, msg.sender) {
        ATLAS = atlas;
    }

    function fulfillRFQ(
        SwapIntent calldata swapIntent,
        address executionEnvironment
    ) public virtual payable {
        require(ERC20(swapIntent.tokenUserSells).balanceOf(address(this)) >= swapIntent.amountUserSells, "Did not receive enough tokenIn");
        require(ERC20(swapIntent.tokenUserBuys).balanceOf(address(this)) >= swapIntent.amountUserBuys, "Not enough tokenOut to fulfill");
        ERC20(swapIntent.tokenUserBuys).transfer(executionEnvironment, swapIntent.amountUserBuys);
        
        // donates 1 ETH to bundler with surplus going to self
        _donateToBundler(1e18, address(this));
    }

    // This ensures a function can only be called through metaFlashCall
    // which includes security checks to work safely with Atlas
    modifier onlySelf() {
        require(msg.sender == address(this), "Not called via metaFlashCall");
        _;
    }

    fallback() external payable {}
    receive() external payable {}
}

contract DoubleDonateRFQSolver is SingleDonateRFQSolver {
    address deployer;
    constructor(address atlas) SingleDonateRFQSolver(atlas) {
        deployer = msg.sender;
    }
    function fulfillRFQ(
        SwapIntent calldata swapIntent,
        address executionEnvironment
    ) public payable override {
        SingleDonateRFQSolver.fulfillRFQ(
            swapIntent,
            executionEnvironment
        );
        
        // This is the 2nd donation attempt - should cause a revert
        _donateToBundler(1e18, address(this));
    }
}