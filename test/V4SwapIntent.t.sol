// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseTest} from "./base/BaseTest.t.sol";
import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {SolverOperation} from "../src/contracts/types/SolverCallTypes.sol";
import {UserOperation} from "../src/contracts/types/UserCallTypes.sol";
import {DAppOperation, DAppConfig} from "../src/contracts/types/DAppApprovalTypes.sol";

import {V4SwapIntentController} from "../src/contracts/examples/intents-example/V4SwapIntent.sol";
import {SolverBase} from "../src/contracts/solver/SolverBase.sol";

import {PoolManager, IPoolManager, PoolKey, Currency, IHooks} from "v4-core/PoolManager.sol";

contract V4SwapIntentTest is BaseTest {
    V4SwapIntentController public swapIntentController;
    PoolManager public poolManager;
    TxBuilder public txBuilder;
    Sig public sig;

    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

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
        swapIntentController = new V4SwapIntentController(address(escrow));        
        atlas.initializeGovernance(address(swapIntentController));
        atlas.integrateDApp(address(swapIntentController));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            controller: address(swapIntentController),
            escrowAddress: address(escrow),
            atlasAddress: address(atlas)
        });

        // Deploy new poolamanger and create a DAI/WETH pool with no hooks
        poolManager = new PoolManager(30000000);

        poolManager.initialize(PoolKey({
            currency0: Currency.wrap(address(DAI)),
            currency1: Currency.wrap(address(WETH)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        }), 1823965582028705631020492031, new bytes(0));

        // Deposit ETH from Searcher signer to pay for searcher's gas 
        // vm.prank(solverOneEOA); 
        // atlas.deposit{value: 1e18}();
    }

    function testAtlasV4SwapIntentWithUniswapSolver() public {

    }

    // function testAtlasV4SwapIntentWithUniswapSolver() public {
    //     // Swap 10 WETH to 100 DAI

    //     // Solver deploys the RFQ solver contract (defined at bottom of this file)
    //     vm.startPrank(solverOneEOA);
    //     UniswapIntentSolver uniswapSolver = new UniswapIntentSolver(address(atlas));
    //     deal(WETH_ADDRESS, address(uniswapSolver), 1e18); // 1 WETH to solver to pay bid
    //     atlas.deposit{value: 1e18}();
    //     vm.stopPrank();

    //     // Input params for Atlas.metacall() - will be populated below
    //     UserOperation memory userOp;
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     DAppOperation memory dAppOp;

    //     vm.startPrank(userEOA);
    //     address executionEnvironment = atlas.createExecutionEnvironment(txBuilder.control());
    //     console.log("executionEnvironment a",executionEnvironment);
    //     vm.stopPrank();
    //     vm.label(address(executionEnvironment), "EXECUTION ENV");

    //     // userOpData is used in delegatecall from exec env to control, calling preOpsCall
    //     // first 4 bytes are "userSelector" param in preOpsCall in DAppControl - swap() selector
    //     // rest of data is "userData" param
        
    //     // swap(SwapIntent calldata) selector = 0x98434997
    //     bytes memory userOpData = abi.encodeWithSelector(SwapIntentController.swap.selector, swapIntent);

    //     // Builds the metaTx and to parts of userOp, signature still to be set
    //     userOp = txBuilder.buildUserOperation({
    //         from: userEOA, // NOTE: Would from ever not be user?
    //         to: address(swapIntentController),
    //         maxFeePerGas: tx.gasprice + 1, // TODO update
    //         value: 0,
    //         deadline: block.number + 2,
    //         data: userOpData
    //     });

    //     // User signs the userOp
    //     // user doees NOT sign the userOp when they are bundling
    //     // (sig.v, sig.r, sig.s) = vm.sign(userPK, atlas.getUserOperationPayload(userOp));
    //     // userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

    //     // Build solver calldata (function selector on solver contract and its params)
    //     bytes memory solverOpData = abi.encodeWithSelector(
    //         UniswapIntentSolver.fulfillWithSwap.selector, 
    //         swapIntent,
    //         executionEnvironment
    //     );

    //     // Builds the SolverOperation
    //     solverOps[0] = txBuilder.buildSolverOperation({
    //         userOp: userOp,
    //         solverOpData: solverOpData,
    //         solverEOA: solverOneEOA,
    //         solverContract: address(uniswapSolver),
    //         bidAmount: 1e18
    //     });

    //     // Solver signs the solverOp
    //     (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlas.getSolverPayload(solverOps[0]));
    //     solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

    //     // Frontend creates dAppOp calldata after seeing rest of data
    //     dAppOp = txBuilder.buildDAppOperation(governanceEOA, userOp, solverOps);

    //     // Frontend signs the dAppOp payload
    //     (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlas.getDAppOperationPayload(dAppOp));
    //     dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

    //     // Check user token balances before
    //     uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);
    //     uint256 userDaiBalanceBefore = DAI.balanceOf(userEOA);

    //     vm.prank(userEOA); // Burn all users WETH except 10 so logs are more readable
    //     WETH.transfer(address(1), userWethBalanceBefore - swapIntent.amountUserSells);
    //     userWethBalanceBefore = WETH.balanceOf(userEOA);

    //     assertTrue(userWethBalanceBefore >= swapIntent.amountUserSells, "Not enough starting WETH");

    //     console.log("\nBEFORE METACALL");
    //     console.log("User WETH balance", WETH.balanceOf(userEOA));
    //     console.log("User DAI balance", DAI.balanceOf(userEOA));
    //     console.log("Solver WETH balance", WETH.balanceOf(address(uniswapSolver)));
    //     console.log("Solver DAI balance", DAI.balanceOf(address(uniswapSolver)));

    //     vm.startPrank(userEOA);

    //     assertFalse(simulator.simUserOperation(userOp), "metasimUserOperationcall tested true");
        
    //     WETH.approve(address(atlas), swapIntent.amountUserSells);

    //     assertTrue(simulator.simUserOperation(userOp), "metasimUserOperationcall tested false");

    //     // Check solver does NOT have DAI - it must use Uniswap to get it during metacall
    //     assertEq(DAI.balanceOf(address(uniswapSolver)), 0, "Solver has DAI before metacall");

    //     // NOTE: Should metacall return something? Feels like a lot of data you might want to know about the tx
    //     atlas.metacall({
    //         userOp: userOp,
    //         solverOps: solverOps,
    //         dAppOp: dAppOp
    //     });
    //     vm.stopPrank();

    //     console.log("\nAFTER METACALL");
    //     console.log("User WETH balance", WETH.balanceOf(userEOA));
    //     console.log("User DAI balance", DAI.balanceOf(userEOA));
    //     console.log("Solver WETH balance", WETH.balanceOf(address(uniswapSolver)));
    //     console.log("Solver DAI balance", DAI.balanceOf(address(uniswapSolver)));

    //     // Check user token balances after
    //     assertEq(WETH.balanceOf(userEOA), userWethBalanceBefore - swapIntent.amountUserSells, "Did not spend enough WETH");
    //     assertEq(DAI.balanceOf(userEOA), userDaiBalanceBefore + swapIntent.amountUserBuys, "Did not receive enough DAI");
    // }
}

contract UniswapV4IntentSolver is SolverBase {
    IPoolManager immutable poolManager;

    constructor(address atlas, IPoolManager manager) SolverBase(atlas, msg.sender) {
        poolManager = manager;
    }

    // function fulfillWithSwap(
    //     SwapIntent calldata swapIntent,
    //     address executionEnvironment
    // ) public onlySelf {
    //     // Checks recieved expected tokens from Atlas on behalf of user to swap
    //     require(ERC20(swapIntent.tokenUserSells).balanceOf(address(this)) >= swapIntent.amountUserSells, "Did not receive enough tokenIn");

    //     address[] memory path = new address[](2);
    //     path[0] = swapIntent.tokenUserSells;
    //     path[1] = swapIntent.tokenUserBuys;

    //     // Attempt to sell all tokens for as many as possible of tokenUserBuys
    //     ERC20(swapIntent.tokenUserSells).approve(address(router), swapIntent.amountUserSells);
    //     router.swapExactTokensForTokens({
    //         amountIn: swapIntent.amountUserSells,
    //         amountOutMin: swapIntent.amountUserBuys, // will revert here if not enough to fulfill intent
    //         path: path,
    //         to: address(this),
    //         deadline: block.timestamp
    //     });

    //     // Send min tokens back to user to fulfill intent, rest are profit for solver
    //     ERC20(swapIntent.tokenUserBuys).transfer(executionEnvironment, swapIntent.amountUserBuys);
    // }

    // This ensures a function can only be called through atlasSolverCall
    // which includes security checks to work safely with Atlas
    modifier onlySelf() {
        require(msg.sender == address(this), "Not called via atlasSolverCall");
        _;
    }

    fallback() external payable {}
    receive() external payable {}
}