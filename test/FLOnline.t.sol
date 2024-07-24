// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { BaseTest } from "./base/BaseTest.t.sol";
import { SolverBase } from "src/contracts/solver/SolverBase.sol";

import { SolverOperation } from "src/contracts/types/SolverOperation.sol";
import { UserOperation } from "src/contracts/types/UserOperation.sol";

import { FastLaneOnlineOuter } from "src/contracts/examples/fastlane-online/FastLaneOnlineOuter.sol";
import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

import { IUniswapV2Router02 } from "test/base/interfaces/IUniswapV2Router.sol";

contract FastLaneOnlineTest is BaseTest {
    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    IUniswapV2Router02 routerV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 defaultGasLimit = 5_000_000;
    uint256 defaultDeadline;

    FastLaneOnlineOuter flOnline;
    address executionEnvironment;

    Sig sig;

    function setUp() public virtual override {
        BaseTest.setUp();

        defaultDeadline = block.number + 1;

        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        vm.startPrank(governanceEOA);
        flOnline = new FastLaneOnlineOuter(address(atlas));
        atlasVerification.initializeGovernance(address(flOnline));
        // FLOnline contract must be registered as its own signatory
        atlasVerification.addSignatory(address(flOnline), address(flOnline));
        vm.stopPrank();

        // This EE wont be deployed until the start of the first metacall
        (executionEnvironment,,) = atlas.getExecutionEnvironment(address(flOnline), address(flOnline));
    }

    function testFastLaneOnlineSwap() public {        
        // First, create the data args the user will pass to the fastOnlineSwap function, which will be intercepted
        // by the solver in the mempool, used to form a solverOp to fulfill the user's SwapIntent, and a
        // frontrunning tx to register this fulfillment solverOp in the FLOnline contract via addSolverOp()

        // Swap 3000 DAI for at least 1 WETH
        SwapIntent memory swapIntent = SwapIntent({
            tokenUserBuys: WETH_ADDRESS,
            minAmountUserBuys: 1 ether,
            tokenUserSells: DAI_ADDRESS,
            amountUserSells: 3000e18
        });

        // Build BaselineCall: swap 3000 DAI for at least 1 WETH via Uniswap V2 Router
        // TODO check this actually works when calling uni v2 router

        address[] memory path = new address[](2);
        path[0] = DAI_ADDRESS;
        path[1] = WETH_ADDRESS;

        BaselineCall memory baselineCall = BaselineCall({
            to: address(routerV2),
            data: abi.encodeCall(routerV2.swapExactTokensForTokens, (
                swapIntent.amountUserSells, // amountIn
                swapIntent.minAmountUserBuys, // amountOutMin
                path, // path = [DAI, WETH]
                userEOA, // to
                defaultDeadline // deadline
            )),
            success: true
        });

        bytes32 userOpHash = atlasVerification.getUserOperationHash(flOnline.getUserOperation({
            swapper: userEOA,
            swapIntent: swapIntent,
            baselineCall: baselineCall,
            deadline: defaultDeadline,
            gas: defaultGasLimit,
            maxFeePerGas: tx.gasprice
        }));

        // Solver frontruns the user's fastOnlineSwap call, registering their solverOp in FLOnline
        vm.startPrank(solverOneEOA);
        // Solver deploys RFQ solver contract
        FLOnlineRFQSolver solver = new FLOnlineRFQSolver(WETH_ADDRESS, address(atlas));
        // Solver bonds 1 ETH in Atlas
        atlas.bond(1e18);

        // Solver creates solverOp
        SolverOperation memory solverOp = SolverOperation({
            from: solverOneEOA,
            to: address(atlas),
            value: 0,
            gas: flOnline.MAX_SOLVER_GAS() - 1,
            maxFeePerGas: tx.gasprice,
            deadline: defaultDeadline,
            solver: address(solver),
            control: address(flOnline),
            userOpHash: userOpHash,
            bidToken: swapIntent.tokenUserBuys,
            bidAmount: swapIntent.minAmountUserBuys,
            data: abi.encodeCall(solver.fulfillRFQ, (swapIntent, executionEnvironment)),
            signature: new bytes(0)
        });

        // Solver signs solverOp
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        flOnline.addSolverOp({
            swapIntent: swapIntent,
            baselineCall: baselineCall,
            deadline: defaultDeadline,
            gas: defaultGasLimit,
            maxFeePerGas: tx.gasprice,
            userOpHash: userOpHash,
            swapper: userEOA,
            solverOp: solverOp
        });
        vm.stopPrank();

        // Give solver and user required assets
        deal(WETH_ADDRESS, userEOA, 0); // Burn user's WETH to start at 0
        deal(DAI_ADDRESS, userEOA, swapIntent.amountUserSells); // 3000 DAI
        deal(WETH_ADDRESS, address(solver), swapIntent.minAmountUserBuys); // 1 WETH
        uint256 userWethBefore = WETH.balanceOf(userEOA);
        uint256 userDaiBefore = DAI.balanceOf(userEOA);

        vm.startPrank(userEOA);

        // User approves FLOnline to take 3000 DAI
        DAI.approve(address(flOnline), swapIntent.amountUserSells);

         // User calls the FastLaneOnline fastOnlineSwap entry point
        (bool result,) = address(flOnline).call{gas: 5_001_000}(
            abi.encodeCall(
                flOnline.fastOnlineSwap, (
                    swapIntent,
                    baselineCall,
                    defaultDeadline,
                    defaultGasLimit,
                    tx.gasprice,
                    userOpHash
                )
            )
        );
        vm.stopPrank();

        // Check the call succeeded
        assertTrue(result, "fastOnlineSwap failed");

        // Check user's balances changed as expected
        assertTrue(WETH.balanceOf(userEOA) >= userWethBefore + swapIntent.minAmountUserBuys, "User did not recieve enough WETH");
        assertEq(DAI.balanceOf(userEOA), userDaiBefore - swapIntent.amountUserSells, "User did not send expected DAI");
    }

    function _verifyBaselineCallSucceeds(BaselineCall memory baselineCall, address caller) public {
        uint256 snapshot = vm.snapshot();
        vm.prank(caller);
        (bool success,) = caller.call(baselineCall.data);
        assertTrue(success, "BaselineCall failed");
        vm.revertTo(snapshot);
    }
}

// This solver magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
contract FLOnlineRFQSolver is SolverBase {

    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) { }

    function fulfillRFQ(SwapIntent calldata swapIntent, address executionEnvironment) public {
        require(
            IERC20(swapIntent.tokenUserSells).balanceOf(address(this)) >= swapIntent.amountUserSells,
            "Did not receive expected amount of tokenUserSells"
        );

        // The solver bid representing user's minAmountUserBuys of tokenUserBuys is sent to the
        // Execution Environment in the payBids modifier logic which runs after this function ends.
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