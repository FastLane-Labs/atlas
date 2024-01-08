// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";

import { SolverOperation } from "../src/contracts/types/SolverCallTypes.sol";
import { UserOperation } from "../src/contracts/types/UserCallTypes.sol";
import { DAppOperation, DAppConfig } from "../src/contracts/types/DAppApprovalTypes.sol";

import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";

import { V4SwapIntentController, SwapData } from "../src/contracts/examples/intents-example/V4SwapIntent.sol";
import { SolverBase } from "../src/contracts/solver/SolverBase.sol";

import { PoolManager, IPoolManager, PoolKey, Currency, IHooks } from "v4-core/PoolManager.sol";

import { PoolModifyPositionTest } from "v4-core/test/PoolModifyPositionTest.sol";
import { PoolSwapTest } from "v4-core/test/PoolSwapTest.sol";

contract V4SwapIntentTest is BaseTest {
    V4SwapIntentController public swapIntentController;
    PoolManager public poolManager;
    PoolKey public poolKey;
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

        // deploy new pool manager
        poolManager = new PoolManager(30_000_000);

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        // Deploy new SwapIntent Controller from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        swapIntentController = new V4SwapIntentController(address(escrow), address(poolManager));
        atlasVerification.initializeGovernance(address(swapIntentController));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            controller: address(swapIntentController),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });

        // Create a DAI/WETH pool with no hooks
        poolKey = PoolKey({
            currency0: Currency.wrap(address(DAI)),
            currency1: Currency.wrap(address(WETH)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        poolManager.initialize(poolKey, 1_797_734_745_375_579_914_506_781_200, new bytes(0));

        // New stuff
        PoolModifyPositionTest modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(poolManager)));

        deal(address(DAI), governanceEOA, 1000e18);
        deal(address(WETH), governanceEOA, 1000e18);

        vm.startPrank(governanceEOA);
        DAI.approve(address(modifyPositionRouter), 1000e18);
        WETH.approve(address(modifyPositionRouter), 1000e18);

        modifyPositionRouter.modifyPosition(
            poolKey,
            IPoolManager.ModifyPositionParams({
                tickLower: -887_220,
                tickUpper: 887_220,
                liquidityDelta: 100_000_000_000_000_000
            }),
            new bytes(0)
        );

        vm.stopPrank();
    }

    function testAtlasV4SwapIntentWithUniswapSolver() public {
        // Try to swap 10 weth

        // Deploy the solver contract
        vm.startPrank(solverOneEOA);
        atlas.bond(1 ether);
        UniswapV4IntentSolver solver = new UniswapV4IntentSolver(WETH_ADDRESS, address(atlas), poolManager);
        vm.stopPrank();

        // Input params for Atlas.metacall() - will be populated below
        UserOperation memory userOp;
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        DAppOperation memory dAppOp;

        vm.startPrank(userEOA);
        address executionEnvironment = atlas.createExecutionEnvironment(txBuilder.control());
        console.log("executionEnvironment a", executionEnvironment);
        vm.stopPrank();
        vm.label(address(executionEnvironment), "EXECUTION ENV");

        // userOpData is used in delegatecall from exec env to control, calling preOpsCall
        // first 4 bytes are "userSelector" param in preOpsCall in DAppControl - swap() selector
        // rest of data is "userData" param

        // swap(SwapIntent calldata) selector = 0x98434997
        bytes memory userOpData = abi.encodeWithSelector(
            V4SwapIntentController.exactInputSingle.selector,
            V4SwapIntentController.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(DAI),
                maxFee: 3000,
                recipient: address(userEOA),
                amountIn: 10e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: address(WETH) < address(DAI)
                    ? 4_295_128_740
                    : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341
            })
        );

        userOp = new UserOperationBuilder()
            .withFrom(userEOA)
            .withTo(address(atlas))
            .withGas(1_000_000)
            .withMaxFeePerGas(tx.gasprice + 1)
            .withNonce(address(atlasVerification))
            .withDapp(address(swapIntentController))
            .withControl(address(swapIntentController))
            .withDeadline(block.number + 2)
            .withData(userOpData)
            .build();

        SwapData memory swapData = SwapData({
            tokenIn: address(WETH),
            tokenOut: address(DAI),
            requestedAmount: 10e18,
            limitAmount: 0,
            recipient: address(userEOA)
        });

        uint256 solverBid = 1e18;

        // Build solver calldata (function selector on solver contract and its params)
        bytes memory solverOpData = abi.encodeWithSelector(
            UniswapV4IntentSolver.fulfillWithSwap.selector, poolKey, swapData, executionEnvironment, solverBid
        );

        // Builds the SolverOperation
        solverOps[0] = new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withSolver(address(solver))
            .withControl(address(swapIntentController))
            .withUserOpHash(userOp)
            .withBidToken(userOp)
            .withBidAmount(solverBid)
            .withData(solverOpData)
            .sign(address(atlasVerification), solverOnePK)
            .build();

        // Frontend creates dAppOp calldata after seeing rest of data
        dAppOp = new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withGas(2_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(address(swapIntentController))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK)
            .build();

        // Check user token balances before
        uint256 userWethBalanceBefore = WETH.balanceOf(userEOA);
        uint256 userDaiBalanceBefore = DAI.balanceOf(userEOA);

        vm.prank(userEOA); // Burn all users WETH except 10 so logs are more readable
        WETH.transfer(address(1), userWethBalanceBefore - uint256(swapData.requestedAmount));
        userWethBalanceBefore = WETH.balanceOf(userEOA);

        assertTrue(userWethBalanceBefore >= uint256(swapData.requestedAmount), "Not enough starting WETH");

        console.log("\nBEFORE METACALL");
        console.log("User WETH balance", WETH.balanceOf(userEOA));
        console.log("User DAI balance", DAI.balanceOf(userEOA));
        console.log("Solver WETH balance", WETH.balanceOf(address(solver)));
        console.log("Solver DAI balance", DAI.balanceOf(address(solver)));

        vm.startPrank(userEOA);

        assertFalse(simulator.simUserOperation(userOp), "metasimUserOperationcall tested true");

        WETH.approve(address(atlas), uint256(swapData.requestedAmount));

        assertTrue(simulator.simUserOperation(userOp), "metasimUserOperationcall tested false");

        // Check solver does NOT have DAI - it must use Uniswap to get it during metacall
        assertEq(DAI.balanceOf(address(solver)), 0, "Solver has DAI before metacall");

        // NOTE: Should metacall return something? Feels like a lot of data you might want to know about the tx
        atlas.metacall({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();

        console.log("\nAFTER METACALL");
        console.log("User WETH balance", WETH.balanceOf(userEOA));
        console.log("User DAI balance", DAI.balanceOf(userEOA));
        console.log("Solver WETH balance", WETH.balanceOf(address(solver)));
        console.log("Solver DAI balance", DAI.balanceOf(address(solver)));

        // Check user token balances after
        assertEq(
            WETH.balanceOf(userEOA),
            userWethBalanceBefore - uint256(swapData.requestedAmount),
            "Did not spend enough WETH"
        );
        assertEq(DAI.balanceOf(userEOA), userDaiBalanceBefore + solverBid, "Did not receive enough DAI");
    }
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

contract UniswapV4IntentSolver is SolverBase {
    IPoolManager immutable poolManager;
    PoolSwapTest immutable swapHelper;

    constructor(address weth, address atlas, IPoolManager manager) SolverBase(weth, atlas, msg.sender) {
        poolManager = manager;
        swapHelper = new PoolSwapTest(manager);
    }

    function fulfillWithSwap(
        PoolKey memory poolKey,
        SwapData memory swap,
        address executionEnvironment,
        uint256 bid
    )
        public
        onlySelf
    {
        // Checks recieved expected tokens from Atlas on behalf of user to swap
        require(
            ERC20(swap.tokenIn).balanceOf(address(this))
                >= (swap.requestedAmount > 0 ? uint256(swap.requestedAmount) : swap.limitAmount - bid),
            "Did not receive enough tokenIn"
        );

        // Make swap on the v4 pool
        ERC20(swap.tokenIn).approve(
            address(swapHelper), swap.requestedAmount > 0 ? uint256(swap.requestedAmount) : swap.limitAmount - bid
        );
        swapHelper.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: swap.tokenIn < swap.tokenOut,
                amountSpecified: swap.requestedAmount,
                sqrtPriceLimitX96: swap.tokenIn < swap.tokenOut
                    ? 4_295_128_740
                    : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341
            }),
            PoolSwapTest.TestSettings({ withdrawTokens: true, settleUsingTransfer: true }),
            new bytes(0)
        );

        // Send min tokens back to user to fulfill intent, rest are profit for solver
        ERC20(swap.tokenOut).transfer(
            executionEnvironment, swap.requestedAmount > 0 ? bid : uint256(-swap.requestedAmount)
        );
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
