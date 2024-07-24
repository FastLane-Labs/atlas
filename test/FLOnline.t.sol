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

    IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    IUniswapV2Router02 routerV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 defaultDeadline = block.timestamp + 1;
    uint256 defaultGasLimit = 5_000_000;

    FastLaneOnlineOuter flOnline;
    address executionEnvironment;

    function setUp() public virtual override {
        BaseTest.setUp();

        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        vm.startPrank(governanceEOA);
        flOnline = new FastLaneOnlineOuter(address(atlas));
        atlasVerification.initializeGovernance(address(flOnline));
        vm.stopPrank();

        // This EE wont be deployed until the start of the first metacall
        (executionEnvironment,,) = atlas.getExecutionEnvironment(address(flOnline), address(flOnline));
    }

    function testFastLaneOnlineSwap() public {        

        // First build the user's SwapIntent and BaselineCall structs

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
                3000e18, // amountIn
                1 ether, // amountOutMin
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

        vm.prank(solverOneEOA);
        FLOnlineRFQSolver solver = new FLOnlineRFQSolver(WETH_ADDRESS, address(atlas));

        SolverOperation memory solverOp = SolverOperation({
            from: solverOneEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
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

        vm.prank(solverOneEOA);
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




        // User calls the FastLaneOnline fastOnlineSwap entry point

        console.log("User WETH before:", WETH.balanceOf(userEOA));
        console.log("User DAI before:", DAI.balanceOf(userEOA));

        vm.prank(userEOA);
        flOnline.fastOnlineSwap({
            swapIntent: swapIntent,
            baselineCall: baselineCall,
            deadline: defaultDeadline,
            gas: defaultGasLimit,
            maxFeePerGas: tx.gasprice,
            userOpHash: userOpHash
        });

        console.log("User WETH after:", WETH.balanceOf(userEOA));
        console.log("User DAI after:", DAI.balanceOf(userEOA));


        
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
        IERC20(swapIntent.tokenUserBuys).transfer(executionEnvironment, swapIntent.minAmountUserBuys);
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