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

    struct FastOnlineSwapArgs {
        SwapIntent swapIntent;
        BaselineCall baselineCall;
        uint256 deadline;
        uint256 gas;
        uint256 maxFeePerGas;
        bytes32 userOpHash;
    }

    // Estimate of gas used in fastOnlineSwap that Atlas does not take a surcharge on
    uint256 constant NON_SURCHARGE_OVERHEAD = 20_000;
    uint256 constant ERR_MARGIN = 0.1e18; // 10% error margin

    IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    IUniswapV2Router02 routerV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 successfulSolverBidAmount = 1.2 ether; // more than baseline swap amountOut
    uint256 defaultGasLimit = 5_000_000;
    uint256 defaultGasPrice;
    uint256 defaultDeadlineBlock;
    uint256 defaultDeadlineTimestamp;

    FastLaneOnlineOuter flOnline;
    address executionEnvironment;

    Sig sig;
    FastOnlineSwapArgs args;

    function setUp() public virtual override {
        BaseTest.setUp();
        vm.rollFork(20_385_779); // ETH was just under $3100 at this block

        defaultDeadlineBlock = block.number + 1;
        defaultDeadlineTimestamp = block.timestamp + 1;
        defaultGasPrice = tx.gasprice;

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

        // Set fastOnlineSwap args to default values
        args = _buildDefaultFastOnlineSwapArgs();

        // User starts with 0 WETH (tokenUserBuys) and 3200 DAI (tokenUserSells)
        deal(args.swapIntent.tokenUserBuys, userEOA, 0); // Burn user's WETH to start at 0
        deal(args.swapIntent.tokenUserSells, userEOA, args.swapIntent.amountUserSells); // 3200 DAI

        // User approves FLOnline to take 3200 DAI
        vm.prank(userEOA);
        IERC20(args.swapIntent.tokenUserSells).approve(address(flOnline), args.swapIntent.amountUserSells);
    }

    function testFLOnlineSwap_OneSolverFulfills_Success() public {
        // First, create the data args the user will pass to the fastOnlineSwap function, which will be intercepted
        // by the solver in the mempool, used to form a solverOp to fulfill the user's SwapIntent, and a
        // frontrunning tx to register this fulfillment solverOp in the FLOnline contract via addSolverOp()

        // Set up the solver contract and register the solverOp in the FLOnline contract
        address winningSolverContract = _setUpSolver(solverOneEOA, solverOnePK, true);

        // User calls fastOnlineSwap, do checks that user and solver balances changed as expected
        _doFastOnlineSwapWithChecks({ winningSolverContract: winningSolverContract, swapCallShouldSucceed: true });
    }

    function testFLOnlineSwap_OneSolverFails_BaselineCallFulfills_Success() public {
        // Set up the solver contract and register the solverOp in the FLOnline contract
        _setUpSolver(solverOneEOA, solverOnePK, false); // solver should fail

        // Check BaselineCall struct is formed correctly and can succeed, revert changes after
        _doBaselineCallWithBalanceChecksThenRevertStateChanges(userEOA, executionEnvironment);

        uint256 snapshotId = vm.snapshot();

        // First, check that fastOnlineSwap fails when 1) no solver succeeds, and 2) the DAppControl/bundler contract
        // has no AtlETH to pay for the metacall gas cost + Atlas gas surcharge.
        _doFastOnlineSwapWithChecks({
            winningSolverContract: address(0), // No winning solver expected
            swapCallShouldSucceed: false
        });

        // Revert state and check again when DAppControl/bundler contract has bonded AtlETH
        vm.revertTo(snapshotId);

        // TODO add mechanism for this in FLOnline - cannot prank in prod
        // FLOnline DAppControl/Bundler deposits and bonds AtlETH to pay gas
        vm.startPrank(address(flOnline));
        deal(address(flOnline), 1e18);
        atlas.depositAndBond{ value: 1e18 }(1e18);
        vm.stopPrank();

        // Now fastOnlineSwap should succeed using BaselineCall for fulfillment, with bundler paying the metacall gas
        // cost + Atlas gas surcharge.
        _doFastOnlineSwapWithChecks({
            winningSolverContract: address(0), // No winning solver expected
            swapCallShouldSucceed: true
        });
    }

    function testFLOnlineSwap_OneSolverFails_BaselineCallReverts_Failure() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ZeroSolvers_BaselineCallFullfills_Success() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ZeroSolvers_BaselineCallReverts_Failure() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ThreeSolvers_ThirdFullfills_Success() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ThreeSolvers_AllFail_BaselineCallFullfills_Success() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ThreeSolvers_AllFail_BaselineCallReverts_Failure() public {
        vm.skip(true);
    }

    // ---------------------------------------------------- //
    //                        Helpers                       //
    // ---------------------------------------------------- //

    function _doFastOnlineSwapWithChecks(address winningSolverContract, bool swapCallShouldSucceed) internal {
        uint256 userWethBefore = WETH.balanceOf(userEOA);
        uint256 userDaiBefore = DAI.balanceOf(userEOA);
        uint256 solverWethBefore = WETH.balanceOf(winningSolverContract);
        uint256 solverDaiBefore = DAI.balanceOf(winningSolverContract);
        uint256 atlasGasSurchargeBefore = atlas.cumulativeSurcharge();
        uint256 estAtlasGasSurcharge = gasleft(); // Reused below during calculations

        vm.prank(userEOA);

        // Do the actual fastOnlineSwap call
        (bool result,) = address(flOnline).call{ gas: args.gas + 1000 }(
            abi.encodeCall(
                flOnline.fastOnlineSwap,
                (args.swapIntent, args.baselineCall, args.deadline, args.gas, args.maxFeePerGas, args.userOpHash)
            )
        );

        // Calculate estimated Atlas gas surcharge taken from call above
        estAtlasGasSurcharge = (estAtlasGasSurcharge - gasleft() - NON_SURCHARGE_OVERHEAD) * defaultGasPrice
            * atlas.ATLAS_SURCHARGE_RATE() / atlas.SCALE();

        assertTrue(
            result == swapCallShouldSucceed,
            swapCallShouldSucceed ? "fastOnlineSwap should have succeeded" : "fastOnlineSwap should have reverted"
        );

        // Return early if transaction expected to revert. Balance checks below would otherwise fail.
        if (!swapCallShouldSucceed) return;

        // Check Atlas gas surcharge earned is within 5% of the estimated gas surcharge
        assertApproxEqRel(
            atlas.cumulativeSurcharge() - atlasGasSurchargeBefore,
            estAtlasGasSurcharge,
            ERR_MARGIN,
            "Atlas gas surcharge not within estimated range"
        );

        // Check user's balances changed as expected
        assertTrue(
            WETH.balanceOf(userEOA) >= userWethBefore + args.swapIntent.minAmountUserBuys,
            "User did not recieve expected WETH"
        );
        assertEq(
            DAI.balanceOf(userEOA), userDaiBefore - args.swapIntent.amountUserSells, "User did not send expected DAI"
        );

        // If winning solver, check balances changed as expected
        if (winningSolverContract != address(0)) {
            assertTrue(
                WETH.balanceOf(winningSolverContract) <= solverWethBefore - args.swapIntent.minAmountUserBuys,
                "Solver did not send expected WETH"
            );
            assertEq(
                DAI.balanceOf(winningSolverContract),
                solverDaiBefore + args.swapIntent.amountUserSells,
                "Solver did not recieve expected DAI"
            );
        }
    }

    // Defaults:
    // SwapIntent: Swap 3200 DAI for at least 1 WETH
    // BaselineCall: Swap 3200 DAI for at least 1 WETH via Uniswap V2 Router
    // UserOpHash: Generated correctly using dapp's getUserOperation() function
    // Deadline: block.number + 1
    // Gas: 5_000_000
    // MaxFeePerGas: tx.gasprice
    function _buildDefaultFastOnlineSwapArgs() internal view returns (FastOnlineSwapArgs memory newArgs) {
        newArgs.swapIntent = SwapIntent({
            tokenUserBuys: WETH_ADDRESS,
            minAmountUserBuys: 1 ether,
            tokenUserSells: DAI_ADDRESS,
            amountUserSells: 3200e18
        });

        address[] memory path = new address[](2);
        path[0] = DAI_ADDRESS;
        path[1] = WETH_ADDRESS;

        newArgs.baselineCall = BaselineCall({
            to: address(routerV2),
            data: abi.encodeCall(
                routerV2.swapExactTokensForTokens,
                (
                    newArgs.swapIntent.amountUserSells, // amountIn
                    newArgs.swapIntent.minAmountUserBuys, // amountOutMin
                    path, // path = [DAI, WETH]
                    executionEnvironment, // to
                    defaultDeadlineTimestamp // deadline
                )
            ),
            success: true // TODO check setting this in arg doesn't impact execution logic
         });

        newArgs.userOpHash = atlasVerification.getUserOperationHash(
            flOnline.getUserOperation({
                swapper: userEOA,
                swapIntent: newArgs.swapIntent,
                baselineCall: newArgs.baselineCall,
                deadline: defaultDeadlineBlock,
                gas: defaultGasLimit,
                maxFeePerGas: defaultGasPrice
            })
        );

        newArgs.deadline = defaultDeadlineBlock;
        newArgs.gas = defaultGasLimit;
        newArgs.maxFeePerGas = defaultGasPrice;
    }

    function _setUpSolver(address solverEOA, uint256 solverPK, bool shouldSucceed) internal returns (address) {
        vm.startPrank(solverEOA);
        // Make sure solver has 1 AtlETH bonded in Atlas
        uint256 bonded = atlas.balanceOfBonded(solverEOA);
        if (bonded < 1e18) {
            uint256 atlETHBalance = atlas.balanceOf(solverEOA);
            if (atlETHBalance < 1e18) {
                deal(solverEOA, 1e18 - atlETHBalance);
                atlas.deposit{ value: 1e18 - atlETHBalance }();
            }
            atlas.bond(1e18 - bonded);
        }

        // Deploy RFQ solver contract
        FLOnlineRFQSolver solver = new FLOnlineRFQSolver(WETH_ADDRESS, address(atlas), shouldSucceed);

        // Solver signs the solverOp
        SolverOperation memory solverOp = _buildSolverOp(solverEOA, solverPK, address(solver));

        // Register solverOp in FLOnline in frontrunning tx
        flOnline.addSolverOp({
            swapIntent: args.swapIntent,
            baselineCall: args.baselineCall,
            deadline: defaultDeadlineBlock,
            gas: defaultGasLimit,
            maxFeePerGas: defaultGasPrice,
            userOpHash: args.userOpHash,
            swapper: userEOA,
            solverOp: solverOp
        });

        // Give solver contract 1 WETH to fulfill user's SwapIntent
        deal(args.swapIntent.tokenUserBuys, address(solver), successfulSolverBidAmount);
        vm.stopPrank();

        // Returns the address of the solver contract deployed here
        return address(solver);
    }

    function _buildSolverOp(
        address solverEOA,
        uint256 solverPK,
        address solverContract
    )
        internal
        returns (SolverOperation memory solverOp)
    {
        solverOp = SolverOperation({
            from: solverEOA,
            to: address(atlas),
            value: 0,
            gas: flOnline.MAX_SOLVER_GAS() - 1,
            maxFeePerGas: defaultGasPrice,
            deadline: defaultDeadlineBlock,
            solver: solverContract,
            control: address(flOnline),
            userOpHash: args.userOpHash,
            bidToken: args.swapIntent.tokenUserBuys,
            bidAmount: successfulSolverBidAmount,
            data: abi.encodeCall(FLOnlineRFQSolver.fulfillRFQ, (args.swapIntent)),
            signature: new bytes(0)
        });
        // Sign solverOp
        (sig.v, sig.r, sig.s) = vm.sign(solverPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
    }

    function _doBaselineCallWithBalanceChecksThenRevertStateChanges(
        address caller,
        address tokenOutRecipient
    )
        internal
    {
        uint256 snapshotId = vm.snapshot();
        uint256 callerDaiBefore = DAI.balanceOf(caller);
        uint256 recipientWethBefore = WETH.balanceOf(tokenOutRecipient);

        vm.startPrank(caller);
        DAI.approve(args.baselineCall.to, args.swapIntent.amountUserSells);
        (bool success,) = args.baselineCall.to.call(args.baselineCall.data);
        vm.stopPrank();
        // Call success and balance checks
        assertTrue(success, "Baseline call should have succeeded");
        assertTrue(
            WETH.balanceOf(tokenOutRecipient) >= recipientWethBefore + args.swapIntent.minAmountUserBuys,
            "Recipient did not recieve expected WETH in baseline call"
        );
        assertEq(
            DAI.balanceOf(caller),
            callerDaiBefore - args.swapIntent.amountUserSells,
            "Caller did not send expected DAI in baseline call"
        );
        //Revert back to state before baseline call was done
        vm.revertTo(snapshotId);
    }
}

// This solver magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
contract FLOnlineRFQSolver is SolverBase {
    bool internal s_shouldSucceed;

    constructor(address weth, address atlas, bool shouldSucceed) SolverBase(weth, atlas, msg.sender) {
        s_shouldSucceed = shouldSucceed;
    }

    function fulfillRFQ(SwapIntent calldata swapIntent) public view {
        require(s_shouldSucceed, "Solver failed intentionally");
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
