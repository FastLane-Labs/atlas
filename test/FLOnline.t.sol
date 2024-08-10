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
import { SwapIntent, BaselineCall, Reputation } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

import { IUniswapV2Router02 } from "test/base/interfaces/IUniswapV2Router.sol";

contract FastLaneOnlineTest is BaseTest {
    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct FastOnlineSwapArgs {
        UserOperation userOp;
        SwapIntent swapIntent;
        BaselineCall baselineCall;
        uint256 deadline;
        uint256 gas;
        uint256 maxFeePerGas;
        bytes32 userOpHash;
    }

    struct BeforeAndAfterVars {
        uint256 userWeth;
        uint256 userDai;
        uint256 solverWeth;
        uint256 solverDai;
        uint256 atlasGasSurcharge;
        Reputation solverOneRep;
        Reputation solverTwoRep;
        Reputation solverThreeRep;
    }

    // defaults to true when solver calls `addSolverOp()`, set to false if the solverOp is expected to not be included
    // in the final solverOps array, or if the solverOp is not attempted as it has a higher index in the sorted array
    // than the winning solverOp.
    struct ExecutionAttemptedInMetacall {
        bool solverOne;
        bool solverTwo;
        bool solverThree;
    }

    uint256 constant ERR_MARGIN = 0.15e18; // 15% error margin

    IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address DAI_ADDRESS = address(DAI);

    IUniswapV2Router02 routerV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 successfulSolverBidAmount = 1.2 ether; // more than baseline swap amountOut
    uint256 defaultMsgValue = 1e17; // 0.1 ETH
    uint256 defaultGasLimit = 2_000_000;
    uint256 defaultGasPrice;
    uint256 defaultDeadlineBlock;
    uint256 defaultDeadlineTimestamp;

    FastLaneOnlineOuter flOnline;
    MockFastLaneOnline flOnlineMock;
    address executionEnvironment;

    Sig sig;
    FastOnlineSwapArgs args;
    BeforeAndAfterVars beforeVars;
    ExecutionAttemptedInMetacall attempted;

    function setUp() public virtual override {
        BaseTest.setUp();
        vm.rollFork(20_385_779); // ETH was just under $3100 at this block

        defaultDeadlineBlock = block.number + 1;
        defaultDeadlineTimestamp = block.timestamp + 1;
        defaultGasPrice = tx.gasprice;

        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        vm.startPrank(governanceEOA);
        flOnlineMock = new MockFastLaneOnline(address(atlas));
        flOnline = new FastLaneOnlineOuter(address(atlas));
        atlasVerification.initializeGovernance(address(flOnline));
        // FLOnline contract must be registered as its own signatory
        atlasVerification.addSignatory(address(flOnline), address(flOnline));
        // Once set up, burn gov role - only the contract itself should be a signatory
        flOnline.transferGovernance(address(govBurner));
        govBurner.burnGovernance(address(flOnline));
        vm.stopPrank();

        // User deploys their FLOnline Execution Environment
        vm.prank(userEOA);
        executionEnvironment = atlas.createExecutionEnvironment(address(flOnline));

        // Set fastOnlineSwap args to default values
        args = _buildDefaultFastOnlineSwapArgs();

        // User starts with 0 WETH (tokenUserBuys) and 3200 DAI (tokenUserSells)
        deal(args.swapIntent.tokenUserBuys, userEOA, 0); // Burn user's WETH to start at 0
        deal(args.swapIntent.tokenUserSells, userEOA, args.swapIntent.amountUserSells); // 3200 DAI
        deal(userEOA, 1e18); // Give user 1 ETH to pay for gas (msg.value is 0.1 ETH per call by default)

        // User approves Atlas to take their DAI to facilitate the swap
        vm.prank(userEOA);
        IERC20(args.swapIntent.tokenUserSells).approve(address(atlas), args.swapIntent.amountUserSells);
    }

    // ---------------------------------------------------- //
    //                     Scenario Tests                   //
    // ---------------------------------------------------- //

    function testFLOnlineSwap_OneSolverFulfills_Success() public {
        // First, create the data args the user will pass to the fastOnlineSwap function, which will be intercepted
        // by the solver in the mempool, used to form a solverOp to fulfill the user's SwapIntent, and a
        // frontrunning tx to register this fulfillment solverOp in the FLOnline contract via addSolverOp()

        // Set up the solver contract and register the solverOp in the FLOnline contract
        address winningSolver = _setUpSolver(solverOneEOA, solverOnePK, successfulSolverBidAmount);

        // User calls fastOnlineSwap, do checks that user and solver balances changed as expected
        _doFastOnlineSwapWithChecks({
            winningSolverEOA: solverOneEOA,
            winningSolver: winningSolver,
            solverCount: 1,
            swapCallShouldSucceed: true
        });
    }

    function testFLOnlineSwap_OneSolverFails_BaselineCallFulfills_Success() public {
        // Set up the solver contract and register the solverOp in the FLOnline contract
        address failingSolver = _setUpSolver(solverOneEOA, solverOnePK, successfulSolverBidAmount);

        // Check BaselineCall struct is formed correctly and can succeed, revert changes after
        _doBaselineCallWithBalanceChecksThenRevertStateChanges({
            caller: userEOA,
            tokenOutRecipient: executionEnvironment,
            shouldSucceed: true
        });

        // Set failingSolver to fail during metacall
        FLOnlineRFQSolver(payable(failingSolver)).setShouldSucceed(false);

        // Now fastOnlineSwap should succeed using BaselineCall for fulfillment, with gas + Atlas gas surcharge paid for
        // by ETH sent as msg.value by user.
        _doFastOnlineSwapWithChecks({
            winningSolverEOA: address(0),
            winningSolver: address(0), // No winning solver expected
            solverCount: 1,
            swapCallShouldSucceed: true
        });
    }

    function testFLOnlineSwap_OneSolverFails_BaselineCallReverts_Failure() public {
        // Set baselineCall incorrectly to intentionally fail
        _setBaselineCallToRevert();

        address solver = _setUpSolver(solverOneEOA, solverOnePK, successfulSolverBidAmount);

        // Check BaselineCall struct is formed correctly and can revert, revert changes after
        _doBaselineCallWithBalanceChecksThenRevertStateChanges({
            caller: userEOA,
            tokenOutRecipient: executionEnvironment,
            shouldSucceed: false
        });

        // Set solver contract to fail during metacall
        FLOnlineRFQSolver(payable(solver)).setShouldSucceed(false);

        // fastOnlineSwap should revert if all solvers fail AND the baseline call also fails
        _doFastOnlineSwapWithChecks({
            winningSolverEOA: address(0),
            winningSolver: address(0), // No winning solver expected
            solverCount: 1,
            swapCallShouldSucceed: false // fastOnlineSwap should revert
         });
    }

    function testFLOnlineSwap_ZeroSolvers_BaselineCallFullfills_Success() public {
        // No solverOps at all
        _doBaselineCallWithBalanceChecksThenRevertStateChanges({
            caller: userEOA,
            tokenOutRecipient: executionEnvironment,
            shouldSucceed: true
        });

        // Now fastOnlineSwap should succeed using BaselineCall for fulfillment, with gas + Atlas gas surcharge paid for
        // by ETH sent as msg.value by user.
        _doFastOnlineSwapWithChecks({
            winningSolverEOA: address(0),
            winningSolver: address(0), // No winning solver expected
            solverCount: 0,
            swapCallShouldSucceed: true
        });
    }

    function testFLOnlineSwap_ZeroSolvers_BaselineCallReverts_Failure() public {
        // No solverOps at all

        // Set baselineCall incorrectly to intentionally fail
        _setBaselineCallToRevert();

        // Check BaselineCall struct is formed correctly and can revert, revert changes after
        _doBaselineCallWithBalanceChecksThenRevertStateChanges({
            caller: executionEnvironment,
            tokenOutRecipient: executionEnvironment,
            shouldSucceed: false
        });

        // fastOnlineSwap should revert if all solvers fail AND the baseline call also fails
        _doFastOnlineSwapWithChecks({
            winningSolverEOA: address(0),
            winningSolver: address(0), // No winning solver expected
            solverCount: 0,
            swapCallShouldSucceed: false // fastOnlineSwap should revert
         });
    }

    function testFLOnlineSwap_ThreeSolvers_ThirdFullfills_Success() public {
        // Set up the solver contracts and register the solverOps in the FLOnline contract
        _setUpSolver(solverOneEOA, solverOnePK, successfulSolverBidAmount);
        _setUpSolver(solverTwoEOA, solverTwoPK, successfulSolverBidAmount + 1e17);
        address winningSolver = _setUpSolver(solverThreeEOA, solverThreePK, successfulSolverBidAmount + 2e17);

        // solverOne does not get included in the sovlerOps array
        attempted.solverOne = false;
        // solverTwo has a lower bid than winner (solverThree) so is not attempted
        attempted.solverTwo = false;

        // User calls fastOnlineSwap, do checks that user and solver balances changed as expected
        _doFastOnlineSwapWithChecks({
            winningSolverEOA: solverThreeEOA,
            winningSolver: winningSolver,
            solverCount: 3,
            swapCallShouldSucceed: true
        });
    }

    function testFLOnlineSwap_ThreeSolvers_AllFail_BaselineCallFullfills_Success() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ThreeSolvers_AllFail_BaselineCallReverts_Failure() public {
        vm.skip(true);
    }

    // ---------------------------------------------------- //
    //                     Unit Tests                     //
    // ---------------------------------------------------- //

    function testFLOnlineSwap_ValidateSwap_Reverts() public {
        vm.skip(true);
    }

    function testFLOnlineSwap_ValidateSwap_UpdatesUserNonce() public {
        vm.skip(true);
        // Check userOp created uses the prev nonce (e.g. if 1 to start)
        // Then the nonce is incremented (e.g. to 2) for use in the next userOp by that swapper
        // These nonces are then converted to the actual nonce used in the userOp:
        // keccak256(FLO nonce + 1, swapper addr)
    }

    function testFLOnline_SortSolverOps_SortsInDescendingOrderOfBid() public {
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        SolverOperation[] memory solverOpsOut;

        // Empty array should return empty array
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        assertEq(solverOpsOut.length, 0, "Not length 0");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "Empty array, not sorted");

        // 1 solverOp array should return same array
        solverOps = new SolverOperation[](1);
        solverOps[0].bidAmount = 1;
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        assertEq(solverOpsOut[0].bidAmount, solverOps[0].bidAmount, "1 solverOp array, not same array");
        assertEq(solverOpsOut.length, 1, "Not length 1");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "1 solverOp array, not sorted");

        // 2 solverOps array should return same array if already sorted
        solverOps = new SolverOperation[](2);
        solverOps[0].bidAmount = 2;
        solverOps[1].bidAmount = 1;
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        assertEq(solverOpsOut[0].bidAmount, solverOps[0].bidAmount, "2 solverOps array, [0] bid mismatch");
        assertEq(solverOpsOut[1].bidAmount, solverOps[1].bidAmount, "2 solverOps array, [1] bid mismatch");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "2 solverOps array, not sorted");

        // 2 solverOps array should return sorted array if not sorted
        solverOps[0].bidAmount = 1;
        solverOps[1].bidAmount = 2;
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        assertEq(solverOpsOut[0].bidAmount, solverOps[1].bidAmount, "2 solverOps array, [1] should be in [0]");
        assertEq(solverOpsOut[1].bidAmount, solverOps[0].bidAmount, "2 solverOps array, [0] should be in [1]");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "2 solverOps array, not sorted");

        // 5 solverOps already sorted (descending) should return same array
        solverOps = new SolverOperation[](5);
        for (uint256 i = 0; i < 5; i++) {
            solverOps[i].bidAmount = 5 - i;
        }
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(solverOpsOut[i].bidAmount, solverOps[i].bidAmount, "5 solverOps sorted, bid mismatch");
        }
        assertEq(solverOpsOut.length, 5, "Not length 5, sorted");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "5 solverOps array, not sorted");

        // 5 solverOps in ascending order should return sorted (descending) array
        for (uint256 i = 0; i < 5; i++) {
            solverOps[i].bidAmount = i + 1;
        }
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(solverOpsOut[i].bidAmount, 5 - i, "5 solverOps opposite order, bid mismatch");
        }
        assertEq(solverOpsOut.length, 5, "Not length 5, opposite order");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "5 solverOps opposite order, not sorted");

        // 5 solverOps in random order should return sorted (descending) array
        solverOps[0].bidAmount = 3;
        solverOps[1].bidAmount = 1;
        solverOps[2].bidAmount = 5;
        solverOps[3].bidAmount = 2;
        solverOps[4].bidAmount = 4;
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        assertEq(solverOpsOut.length, 5, "Not length 5, random order");
        assertTrue(_isSolverOpsSorted(solverOpsOut), "5 solverOps random order, not sorted");
    }

    function testFLOnline_SortSolverOps_DropsZeroBids() public {
        SolverOperation[] memory solverOps = new SolverOperation[](5);
        SolverOperation[] memory solverOpsOut;

        // 5 solverOps with 0 bid should return empty array
        for (uint256 i = 0; i < 5; i++) {
            solverOps[i].bidAmount = 0;
        }
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);
        assertEq(solverOpsOut.length, 0, "5 solverOps with 0 bid, not empty");

        // 5 solverOps with 0 bid mixed with non-zero bids should return sorted array with 0 bids dropped
        solverOps[0].bidAmount = 0;
        solverOps[1].bidAmount = 1;
        solverOps[2].bidAmount = 0;
        solverOps[3].bidAmount = 2;
        solverOps[4].bidAmount = 0;
        solverOpsOut = flOnlineMock.sortSolverOps(solverOps);

        assertEq(solverOpsOut.length, 2, "5 solverOps with 0 bid mixed, not length 2");
        assertEq(solverOpsOut[0].bidAmount, 2, "5 solverOps with 0 bid mixed, [0] bid mismatch");
        assertEq(solverOpsOut[1].bidAmount, 1, "5 solverOps with 0 bid mixed, [1] bid mismatch");
    }

    function testFLOnline_SetWinningSolver_DoesNotUpdateForUnexpectedCaller() public {
        (address userEE,,) = atlas.getExecutionEnvironment(userEOA, address(flOnlineMock));
        assertEq(flOnlineMock.getWinningSolver(), address(0), "winningSolver should start empty");

        vm.prank(userEOA);
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), address(0), "err 1 - winningSolver should be empty");

        vm.prank(governanceEOA);
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), address(0), "err 2 - winningSolver should be empty");

        vm.prank(solverOneEOA);
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), address(0), "err 3 - winningSolver should be empty");

        vm.prank(address(flOnlineMock));
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), address(0), "err 4 - winningSolver should be empty");

        vm.prank(address(atlas));
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), address(0), "err 5 - winningSolver should be empty");

        vm.prank(userEE); // userEE is valid caller, but still wont set if userEOA is not in userLock
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), address(0), "err 6 - winningSolver should be empty");

        // Only valid caller: the user's EE when userEOA is stored in userLock
        flOnlineMock.setUserLock(userEOA);
        assertEq(flOnlineMock.getUserLock(), userEOA, "userLock should be userEOA");
        vm.prank(userEE);
        flOnlineMock.setWinningSolver(solverOneEOA);
        assertEq(flOnlineMock.getWinningSolver(), solverOneEOA, "winningSolver should be solverOneEOA");
    }

    // TODO add tests when solverOp is valid, but does not outperform baseline call, baseline call used instead

    // ---------------------------------------------------- //
    //                        Helpers                       //
    // ---------------------------------------------------- //

    function _doFastOnlineSwapWithChecks(
        address winningSolverEOA,
        address winningSolver,
        uint256 solverCount,
        bool swapCallShouldSucceed
    )
        internal
    {
        beforeVars.userWeth = WETH.balanceOf(userEOA);
        beforeVars.userDai = DAI.balanceOf(userEOA);
        beforeVars.solverWeth = WETH.balanceOf(winningSolver);
        beforeVars.solverDai = DAI.balanceOf(winningSolver);
        beforeVars.atlasGasSurcharge = atlas.cumulativeSurcharge();
        beforeVars.solverOneRep = flOnline.solverReputation(solverOneEOA);
        beforeVars.solverTwoRep = flOnline.solverReputation(solverTwoEOA);
        beforeVars.solverThreeRep = flOnline.solverReputation(solverThreeEOA);
        uint256 estAtlasGasSurcharge = gasleft(); // Reused below during calculations

        vm.prank(userEOA);

        // Do the actual fastOnlineSwap call
        (bool result,) = address(flOnline).call{ gas: args.gas + 1000, value: defaultMsgValue }(
            abi.encodeCall(flOnline.fastOnlineSwap, (args.userOp))
        );

        // Calculate estimated Atlas gas surcharge taken from call above
        estAtlasGasSurcharge =
            (estAtlasGasSurcharge - gasleft()) * defaultGasPrice * atlas.ATLAS_SURCHARGE_RATE() / atlas.SCALE();

        assertTrue(
            result == swapCallShouldSucceed,
            swapCallShouldSucceed ? "fastOnlineSwap should have succeeded" : "fastOnlineSwap should have reverted"
        );

        // Return early if transaction expected to revert. Balance checks below would otherwise fail.
        if (!swapCallShouldSucceed) return;

        // Check Atlas gas surcharge earned is within 15% of the estimated gas surcharge
        assertApproxEqRel(
            atlas.cumulativeSurcharge() - beforeVars.atlasGasSurcharge,
            estAtlasGasSurcharge,
            ERR_MARGIN,
            "Atlas gas surcharge not within estimated range"
        );

        // Check user's balances changed as expected
        assertTrue(
            WETH.balanceOf(userEOA) >= beforeVars.userWeth + args.swapIntent.minAmountUserBuys,
            "User did not recieve expected WETH"
        );
        assertEq(
            DAI.balanceOf(userEOA),
            beforeVars.userDai - args.swapIntent.amountUserSells,
            "User did not send expected DAI"
        );

        // If winning solver, check balances changed as expected
        if (winningSolver != address(0)) {
            assertTrue(
                WETH.balanceOf(winningSolver) <= beforeVars.solverWeth - args.swapIntent.minAmountUserBuys,
                "Solver did not send expected WETH"
            );
            assertEq(
                DAI.balanceOf(winningSolver),
                beforeVars.solverDai + args.swapIntent.amountUserSells,
                "Solver did not recieve expected DAI"
            );
        }

        // Check reputation of all solvers involved
        if (solverCount > 0) {
            _checkReputationChanges({
                name: "solverOneEOA",
                repBefore: beforeVars.solverOneRep,
                repAfter: flOnline.solverReputation(solverOneEOA),
                won: winningSolverEOA == solverOneEOA,
                executionAttempted: attempted.solverOne
            });
        }
        if (solverCount > 1) {
            _checkReputationChanges({
                name: "solverTwoEOA",
                repBefore: beforeVars.solverTwoRep,
                repAfter: flOnline.solverReputation(solverTwoEOA),
                won: winningSolverEOA == solverTwoEOA,
                executionAttempted: attempted.solverTwo
            });
        }
        if (solverCount > 2) {
            _checkReputationChanges({
                name: "solverThreeEOA",
                repBefore: beforeVars.solverThreeRep,
                repAfter: flOnline.solverReputation(solverThreeEOA),
                won: winningSolverEOA == solverThreeEOA,
                executionAttempted: attempted.solverThree
            });
        }
    }

    // Defaults:
    // SwapIntent: Swap 3200 DAI for at least 1 WETH
    // BaselineCall: Swap 3200 DAI for at least 1 WETH via Uniswap V2 Router
    // UserOpHash: Generated correctly using dapp's getUserOperation() function
    // Deadline: block.number + 1
    // Gas: 2_000_000
    // MaxFeePerGas: tx.gasprice
    function _buildDefaultFastOnlineSwapArgs() internal returns (FastOnlineSwapArgs memory newArgs) {
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
            value: 0
        });

        (newArgs.userOp, newArgs.userOpHash) = flOnline.getUserOperationAndHash({
            swapper: userEOA,
            swapIntent: newArgs.swapIntent,
            baselineCall: newArgs.baselineCall,
            deadline: defaultDeadlineBlock,
            gas: defaultGasLimit,
            maxFeePerGas: defaultGasPrice
        });

        // User signs userOp
        (sig.v, sig.r, sig.s) = vm.sign(userPK, newArgs.userOpHash);
        newArgs.userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        newArgs.deadline = defaultDeadlineBlock;
        newArgs.gas = defaultGasLimit;
        newArgs.maxFeePerGas = defaultGasPrice;
    }

    function _setUpSolver(address solverEOA, uint256 solverPK, uint256 bidAmount) internal returns (address) {
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
        bytes32 salt = keccak256(abi.encodePacked(address(flOnline), solverEOA, bidAmount));
        FLOnlineRFQSolver solver = new FLOnlineRFQSolver{ salt: salt }(WETH_ADDRESS, address(atlas));

        // Solver signs the solverOp
        SolverOperation memory solverOp = _buildSolverOp(solverEOA, solverPK, address(solver), bidAmount);

        // Give solver contract 1 WETH to fulfill user's SwapIntent
        deal(args.swapIntent.tokenUserBuys, address(solver), bidAmount);

        // Register solverOp in FLOnline in frontrunning tx
        flOnline.addSolverOp({ userOp: args.userOp, solverOp: solverOp });
        vm.stopPrank();

        if (solverEOA == solverOneEOA) attempted.solverOne = true;
        if (solverEOA == solverTwoEOA) attempted.solverTwo = true;
        if (solverEOA == solverThreeEOA) attempted.solverThree = true;

        // Returns the address of the solver contract deployed here
        return address(solver);
    }

    function _buildSolverOp(
        address solverEOA,
        uint256 solverPK,
        address solverContract,
        uint256 bidAmount
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
            bidAmount: bidAmount,
            data: abi.encodeCall(FLOnlineRFQSolver.fulfillRFQ, (args.swapIntent)),
            signature: new bytes(0)
        });
        // Sign solverOp
        (sig.v, sig.r, sig.s) = vm.sign(solverPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
    }

    function _doBaselineCallWithBalanceChecksThenRevertStateChanges(
        address caller,
        address tokenOutRecipient,
        bool shouldSucceed
    )
        internal
    {
        uint256 snapshotId = vm.snapshot();
        uint256 callerDaiBefore = DAI.balanceOf(caller);
        uint256 recipientWethBefore = WETH.balanceOf(tokenOutRecipient);

        if (callerDaiBefore < args.swapIntent.amountUserSells) {
            deal(address(DAI), caller, args.swapIntent.amountUserSells);
            callerDaiBefore = DAI.balanceOf(caller);
        }

        vm.startPrank(caller);
        DAI.approve(args.baselineCall.to, args.swapIntent.amountUserSells);
        (bool success,) = args.baselineCall.to.call(args.baselineCall.data);
        vm.stopPrank();

        assertTrue(
            success == shouldSucceed,
            shouldSucceed ? "Baseline call should have succeeded" : "Baseline call should have reverted"
        );

        if (!shouldSucceed) {
            vm.revertTo(snapshotId);
            return;
        }

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

    function _setBaselineCallToRevert() internal {
        // Everything correct except amountOutMin is too high
        address[] memory path = new address[](2);
        path[0] = DAI_ADDRESS;
        path[1] = WETH_ADDRESS;

        args.baselineCall = BaselineCall({
            to: address(routerV2),
            data: abi.encodeCall(
                routerV2.swapExactTokensForTokens,
                (
                    args.swapIntent.amountUserSells, // amountIn
                    9999e18, // BAD (unrealistic) amountOutMin
                    path, // path = [DAI, WETH]
                    executionEnvironment, // to
                    defaultDeadlineTimestamp // deadline
                )
            ),
            value: 0
        });

        // Need to update the userOp with changes to baseline call
        (args.userOp, args.userOpHash) = flOnline.getUserOperationAndHash({
            swapper: userEOA,
            swapIntent: args.swapIntent,
            baselineCall: args.baselineCall,
            deadline: defaultDeadlineBlock,
            gas: defaultGasLimit,
            maxFeePerGas: defaultGasPrice
        });

        // User signs userOp
        (sig.v, sig.r, sig.s) = vm.sign(userPK, args.userOpHash);
        args.userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
    }

    // Checks the solverOps array is sorted in descending order of bidAmount
    function _isSolverOpsSorted(SolverOperation[] memory solverOps) internal pure returns (bool) {
        if (solverOps.length < 2) return true;
        for (uint256 i = 0; i < solverOps.length - 1; i++) {
            if (solverOps[i].bidAmount < solverOps[i + 1].bidAmount) {
                return false;
            }
        }
        return true;
    }

    function _checkReputationChanges(
        string memory name,
        Reputation memory repBefore,
        Reputation memory repAfter,
        bool won,
        bool executionAttempted
    )
        internal
        pure
    {
        if (executionAttempted) {
            if (won) {
                assertGt(
                    repAfter.successCost,
                    repBefore.successCost,
                    string.concat(name, " successCost not updated correctly")
                );
                assertEq(
                    repAfter.failureCost,
                    repBefore.failureCost,
                    string.concat(name, " failureCost should not have changed")
                );
            } else {
                assertGt(
                    repAfter.failureCost,
                    repBefore.failureCost,
                    string.concat(name, " failureCost not updated correctly")
                );
                assertEq(
                    repAfter.successCost,
                    repBefore.successCost,
                    string.concat(name, " successCost should not have changed")
                );
            }
        } else {
            // not attempted due to not being included in solverOps, or due to having a lower bid than the winning
            // solver and thus a higher index in the sorted array. No change in reputation expected.
            assertEq(
                repAfter.successCost, repBefore.successCost, string.concat(name, " successCost should not have changed")
            );
            assertEq(
                repAfter.failureCost, repBefore.failureCost, string.concat(name, " failureCost should not have changed")
            );
        }
    }
}

// This solver magically has the tokens needed to fulfil the user's swap.
// This might involve an offchain RFQ system
contract FLOnlineRFQSolver is SolverBase {
    bool internal s_shouldSucceed;

    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) {
        s_shouldSucceed = true; // should succeed by default, can be set to false
    }

    function shouldSucceed() public view returns (bool) {
        return s_shouldSucceed;
    }

    function setShouldSucceed(bool succeed) public {
        s_shouldSucceed = succeed;
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

// Mock contract to expose internal FLOnline functions for unit testing
contract MockFastLaneOnline is FastLaneOnlineOuter {
    constructor(address _atlas) FastLaneOnlineOuter(_atlas) { }

    function sortSolverOps(SolverOperation[] memory solverOps) external pure returns (SolverOperation[] memory) {
        return _sortSolverOps(solverOps);
    }

    // ---------------------------------------------------- //
    //                  BaseStorage.sol                     //
    // ---------------------------------------------------- //

    function getUserLock() external view returns (address) {
        return _getUserLock();
    }

    function setUserLock(address user) external {
        _setUserLock(user);
    }

    function getWinningSolver() external view returns (address) {
        return _getWinningSolver();
    }
}
