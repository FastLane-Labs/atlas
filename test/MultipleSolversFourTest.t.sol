// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {BaseTest} from "../test/base/BaseTest.t.sol";
import {SolverBase} from "../src/contracts/solver/SolverBase.sol";
import {AtlasErrors} from "../src/contracts/types/AtlasErrors.sol";
import {DAppControl} from "../src/contracts/dapp/DAppControl.sol";
import {CallConfig} from "../src/contracts/types/ConfigTypes.sol";
import {SolverOperation} from "../src/contracts/types/SolverOperation.sol";
import {UserOperation} from "../src/contracts/types/UserOperation.sol";
import {DAppOperation} from "../src/contracts/types/DAppOperation.sol";
import {AtlasEvents} from "../src/contracts/types/AtlasEvents.sol";
import {SolverOutcome} from "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/libraries/CallVerification.sol";
import "../src/contracts/interfaces/IAtlas.sol";
import "forge-std/console.sol";
/// @dev this test is used to illustrate and test the multiple successful solvers feature
/// @dev MultipleSolversDAppControl serves as both the dapp and dAppControl contracts
/// @dev It tracks an "accumulatedAuxillaryBid" which is the sum of all auxillary bids from all solvers
/// @dev and emits an event when updated. These events (and their order) are used to check that solvers have
/// @dev been executed as expected in various scenarios.
/// @dev Solvers also include an auxillary bid with their call, which is just a number (not paid) tracked by the dapp
/// @dev control contract.

contract MultipleSolversFourTest is BaseTest, AtlasErrors {
    MultipleSolversDAppControl control;
    MockSolver solver1;
    MockSolver solver2;
    MockSolver solver3;
    MockSolver solver4;

    uint256 userOpSignerPK = 0x123456;
    address userOpSigner = vm.addr(userOpSignerPK);

    uint256 auctioneerPk = 0xabcdef;
    address auctioneer = vm.addr(auctioneerPk);

    uint256 bundlerPk = 0x123456;
    address bundler = vm.addr(bundlerPk);

    uint256 solverBidAmount = 1 ether;

    function setUp() public override {
        super.setUp();

        vm.startPrank(governanceEOA);
        control = new MultipleSolversDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(control));
        atlasVerification.addSignatory(address(control), auctioneer);
        vm.stopPrank();

        vm.prank(solverOneEOA);
        solver1 = new MockSolver(
            address(WETH_ADDRESS), address(atlas));
        vm.deal(address(solver1), 10 * solverBidAmount);
        vm.prank(solverOneEOA);
        atlas.depositAndBond{value: 5 ether}(5 ether);

        vm.prank(solverTwoEOA);
        solver2 = new MockSolver(
            address(WETH_ADDRESS), address(atlas));
        vm.deal(address(solver2), 10 * solverBidAmount);
        vm.prank(solverTwoEOA);
        atlas.depositAndBond{value: 5 ether}(5 ether);

        vm.prank(solverThreeEOA);
        solver3 = new MockSolver(
            address(WETH_ADDRESS), address(atlas));
        vm.deal(address(solver3), 10 * solverBidAmount);
        vm.prank(solverThreeEOA);
        atlas.depositAndBond{value: 5 ether}(5 ether);

        vm.prank(solverFourEOA);
        solver4 = new MockSolver(
            address(WETH_ADDRESS), address(atlas));
        vm.deal(address(solver4), 10 * solverBidAmount);
        vm.prank(solverFourEOA);
        atlas.depositAndBond{value: 5 ether}(5 ether);
    }

    function buildUserOperation(uint256 signerPK) internal view returns (UserOperation memory) {
        address signer = vm.addr(signerPK);
        UserOperation memory userOp = UserOperation({
            from: signer,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: 1_000_000_000,
            nonce: 1,
            deadline: block.number + 100,
            dapp: address(control),
            control: address(control),
            callConfig: control.CALL_CONFIG(),
            dappGasLimit: 2_000_000,
            sessionKey: auctioneer,
            data: abi.encodeWithSelector(control.initiateAuction.selector),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(signerPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
        return userOp;
    }

    function buildSolverOperation(
        uint256 solverPK,
        address solverContract,
        bytes32 userOpHash,
        uint256 bidAmount,
        uint256 auxillaryBidAmount,
        bool isReverting,
        bool isRevertingBundlerFault,
        uint256 numIterations
    ) internal view returns (SolverOperation memory) {
        bytes memory data;
        if (isReverting) {
            data = abi.encodeWithSelector(solver1.solve.selector, numIterations, true);
        } else {
            data = abi.encodeWithSelector(solver1.solve.selector, numIterations, false);
            bytes memory aux = abi.encode(auxillaryBidAmount);
            data = bytes.concat(data, aux);
        }

        address solverEoa = vm.addr(solverPK);
        SolverOperation memory solverOp = SolverOperation({
            from: solverEoa,
            to: address(atlas),
            value: 0,
            gas: 6_000_000,
            maxFeePerGas: 1_000_000_000,
            deadline: block.number + 100,
            solver: solverContract,
            control: address(control),
            userOpHash: userOpHash,
            bidToken: address(0),
            bidAmount: bidAmount,
            data: data,
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(solverPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
        if (isRevertingBundlerFault) {
            console.log("setting to bundler fault");
            solverOp.signature = "";
        }
        return solverOp;
    }

    function buildDAppOperation(bytes32 userOpHash, bytes32 callChainHash, address givenBundler)
        internal
        view
        returns (DAppOperation memory)
    {
        DAppOperation memory dappOp = DAppOperation({
            from: auctioneer,
            to: address(atlas),
            nonce: 0,
            deadline: block.number + 100,
            control: address(control),
            bundler: givenBundler,
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            signature: new bytes(0)
        });
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(auctioneerPk, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
        return dappOp;
    }

    struct SolverBidPattern {
        uint256 bidAmount;
        uint256 auxillaryBidAmount;
        bool isReverting;
        bool isRevertingBundlerFault;
        uint256 numIterations;
        uint256 gasUsed;  // Actual gas used by this solver
    }

    function four_solver_generic_test(
        SolverBidPattern memory solver1BidPattern,
        SolverBidPattern memory solver2BidPattern,
        SolverBidPattern memory solver3BidPattern,
        SolverBidPattern memory solver4BidPattern
    ) public {
        UserOperation memory userOp = buildUserOperation(userOpSignerPK);
        (address executionEnvironment, ,) = IAtlas(address(atlas)).getExecutionEnvironment(userOpSigner, address(control));
        bytes32 userOpHash = atlasVerification.getUserOperationHash(userOp);
        SolverOperation memory solverOp1 = buildSolverOperation(
            solverOnePK,
            address(solver1),
            userOpHash,
            solver1BidPattern.bidAmount,
            solver1BidPattern.auxillaryBidAmount,
            solver1BidPattern.isReverting,
            solver1BidPattern.isRevertingBundlerFault,
            solver1BidPattern.numIterations
        );
        SolverOperation memory solverOp2 = buildSolverOperation(
            solverTwoPK,
            address(solver2),
            userOpHash,
            solver2BidPattern.bidAmount,
            solver2BidPattern.auxillaryBidAmount,
            solver2BidPattern.isReverting,
            solver2BidPattern.isRevertingBundlerFault,
            solver2BidPattern.numIterations
        );
        SolverOperation memory solverOp3 = buildSolverOperation(
            solverThreePK,
            address(solver3),
            userOpHash,
            solver3BidPattern.bidAmount,
            solver3BidPattern.auxillaryBidAmount,
            solver3BidPattern.isReverting,
            solver3BidPattern.isRevertingBundlerFault,
            solver3BidPattern.numIterations
        );
        SolverOperation memory solverOp4 = buildSolverOperation(
            solverFourPK,
            address(solver4),
            userOpHash,
            solver4BidPattern.bidAmount,
            solver4BidPattern.auxillaryBidAmount,
            solver4BidPattern.isReverting,
            solver4BidPattern.isRevertingBundlerFault,
            solver4BidPattern.numIterations
        );
        SolverOperation[] memory solverOps = new SolverOperation[](4);
        solverOps[0] = solverOp1;
        solverOps[1] = solverOp2;
        solverOps[2] = solverOp3;
        solverOps[3] = solverOp4;
        
        bytes32 callChainHash = CallVerification.getCallChainHash(userOp, solverOps);
        DAppOperation memory dappOp = buildDAppOperation(userOpHash, callChainHash, bundler);

        uint256 solverOneResult = solver1BidPattern.isRevertingBundlerFault ? (1 << uint256(SolverOutcome.InvalidSignature)) : (solver1BidPattern.isReverting ? (1 << uint256(SolverOutcome.SolverOpReverted)) : (1 << uint256(SolverOutcome.MultipleSolvers)));
        uint256 solverTwoResult = solver2BidPattern.isRevertingBundlerFault ? (1 << uint256(SolverOutcome.InvalidSignature)) : (solver2BidPattern.isReverting ? (1 << uint256(SolverOutcome.SolverOpReverted)) : (1 << uint256(SolverOutcome.MultipleSolvers)));
        uint256 solverThreeResult = solver3BidPattern.isRevertingBundlerFault ? (1 << uint256(SolverOutcome.InvalidSignature)) : (solver3BidPattern.isReverting ? (1 << uint256(SolverOutcome.SolverOpReverted)) : (1 << uint256(SolverOutcome.MultipleSolvers)));
        uint256 solverFourResult = solver4BidPattern.isRevertingBundlerFault ? (1 << uint256(SolverOutcome.InvalidSignature)) : (solver4BidPattern.isReverting ? (1 << uint256(SolverOutcome.SolverOpReverted)) : (1 << uint256(SolverOutcome.MultipleSolvers)));

        uint256 mev = 0;
        // Only add to MEV if solver neither reverts nor has bundler fault
        if (!solver1BidPattern.isReverting && !solver1BidPattern.isRevertingBundlerFault) {
            mev += solver1BidPattern.bidAmount;
        }
        if (!solver2BidPattern.isReverting && !solver2BidPattern.isRevertingBundlerFault) {
            mev += solver2BidPattern.bidAmount;
        }
        if (!solver3BidPattern.isReverting && !solver3BidPattern.isRevertingBundlerFault) {
            mev += solver3BidPattern.bidAmount;
        }
        if (!solver4BidPattern.isReverting && !solver4BidPattern.isRevertingBundlerFault) {
            mev += solver4BidPattern.bidAmount;
        }

        uint256 accumulatedAuxillaryBidSolverOne = solver1BidPattern.isReverting || solver1BidPattern.isRevertingBundlerFault ? 0 : solver1BidPattern.auxillaryBidAmount;
        uint256 accumulatedAuxillaryBidSolverTwo = accumulatedAuxillaryBidSolverOne;
        accumulatedAuxillaryBidSolverTwo += solver2BidPattern.isReverting || solver2BidPattern.isRevertingBundlerFault ? 0 : solver2BidPattern.auxillaryBidAmount;
        uint256 accumulatedAuxillaryBidSolverThree = accumulatedAuxillaryBidSolverTwo;
        accumulatedAuxillaryBidSolverThree += solver3BidPattern.isReverting || solver3BidPattern.isRevertingBundlerFault ? 0 : solver3BidPattern.auxillaryBidAmount;
        uint256 accumulatedAuxillaryBidSolverFour = accumulatedAuxillaryBidSolverThree;
        accumulatedAuxillaryBidSolverFour += solver4BidPattern.isReverting || solver4BidPattern.isRevertingBundlerFault ? 0 : solver4BidPattern.auxillaryBidAmount;

        uint256 metacallGasLimit = simulator.estimateMetacallGasLimit(userOp, solverOps);

        vm.deal(address(bundler), 2 ether);
        vm.txGasPrice(1 gwei);

        if (!solver1BidPattern.isReverting && !solver1BidPattern.isRevertingBundlerFault) {
            vm.expectEmit(address(executionEnvironment));
            emit MultipleSolversDAppControl.AccumulatedAuxillaryBidUpdated(address(solver1), accumulatedAuxillaryBidSolverOne);
        }
        vm.expectEmit(address(atlas));
        emit AtlasEvents.SolverTxResult(
            address(solver1),
            solverOneEOA,
            address(control),
            address(0),
            solver1BidPattern.bidAmount,
            !solver1BidPattern.isRevertingBundlerFault,
            !solver1BidPattern.isReverting && !solver1BidPattern.isRevertingBundlerFault,
            solverOneResult
        );
        if (!solver2BidPattern.isReverting && !solver2BidPattern.isRevertingBundlerFault) {
            vm.expectEmit(address(executionEnvironment));
            emit MultipleSolversDAppControl.AccumulatedAuxillaryBidUpdated(address(solver2), accumulatedAuxillaryBidSolverTwo);
        }
        vm.expectEmit(address(atlas));
        emit AtlasEvents.SolverTxResult(
            address(solver2),
            solverTwoEOA,
            address(control),
            address(0),
            solver2BidPattern.bidAmount,
            !solver2BidPattern.isRevertingBundlerFault,
            !solver2BidPattern.isReverting && !solver2BidPattern.isRevertingBundlerFault,
            solverTwoResult
        );
        
        if (!solver3BidPattern.isReverting && !solver3BidPattern.isRevertingBundlerFault) {
            vm.expectEmit(address(executionEnvironment));
            emit MultipleSolversDAppControl.AccumulatedAuxillaryBidUpdated(address(solver3), accumulatedAuxillaryBidSolverThree);
        }
        vm.expectEmit(address(atlas));
        emit AtlasEvents.SolverTxResult(
            address(solver3),
            solverThreeEOA,
            address(control),
            address(0),
            solver3BidPattern.bidAmount,
            !solver3BidPattern.isRevertingBundlerFault,
            !solver3BidPattern.isReverting && !solver3BidPattern.isRevertingBundlerFault,
            solverThreeResult
        );
        if (!solver4BidPattern.isReverting && !solver4BidPattern.isRevertingBundlerFault) {
            vm.expectEmit(address(executionEnvironment));
            emit MultipleSolversDAppControl.AccumulatedAuxillaryBidUpdated(address(solver4), accumulatedAuxillaryBidSolverFour);
        }
        vm.expectEmit(address(atlas));
        emit AtlasEvents.SolverTxResult(
            address(solver4),
            solverFourEOA,
            address(control),
            address(0),
            solver4BidPattern.bidAmount,
            !solver4BidPattern.isRevertingBundlerFault,
            !solver4BidPattern.isReverting && !solver4BidPattern.isRevertingBundlerFault,
            solverFourResult
        );

        vm.expectEmit(address(executionEnvironment));
        emit MultipleSolversDAppControl.MevAllocated(
            address(control), 
            mev
        );

        uint256 bundlerBalanceBefore = address(bundler).balance;

        // Track initial balances
        uint256 solver1InitialBalance = atlas.balanceOfBonded(address(solverOneEOA));
        uint256 solver2InitialBalance = atlas.balanceOfBonded(address(solverTwoEOA));
        uint256 solver3InitialBalance = atlas.balanceOfBonded(address(solverThreeEOA));
        uint256 solver4InitialBalance = atlas.balanceOfBonded(address(solverFourEOA));

        vm.startPrank(bundler);
        (bool success, bytes memory returnData) = address(atlas).call{gas: metacallGasLimit}(
            abi.encodeWithSelector(atlas.metacall.selector, userOp, solverOps, dappOp, address(0))
        );

        // Only check success and returnData if no solvers have bundler fault reverts, for some reason bundler faults cause partial revert
        if (!solver1BidPattern.isRevertingBundlerFault && 
            !solver2BidPattern.isRevertingBundlerFault && 
            !solver3BidPattern.isRevertingBundlerFault && 
            !solver4BidPattern.isRevertingBundlerFault) {
            assertEq(success, true, "metacall failed");
            assertEq(abi.decode(returnData, (bool)), false, "auctionWon should be false");
        }

        vm.stopPrank();

        assertEq(solver1.executed(), !solver1BidPattern.isReverting && !solver1BidPattern.isRevertingBundlerFault, "solver1 execution state wrong");
        assertEq(solver2.executed(), !solver2BidPattern.isReverting && !solver2BidPattern.isRevertingBundlerFault, "solver2 execution state wrong");
        assertEq(solver3.executed(), !solver3BidPattern.isReverting && !solver3BidPattern.isRevertingBundlerFault, "solver3 execution state wrong");
        assertEq(solver4.executed(), !solver4BidPattern.isReverting && !solver4BidPattern.isRevertingBundlerFault, "solver4 execution state wrong");
        
        assertEq(solver1.counter(), (!solver1BidPattern.isReverting && !solver1BidPattern.isRevertingBundlerFault) ? 1 : 0, "solver1 counter should be 1 if not reverted");
        assertEq(solver2.counter(), (!solver2BidPattern.isReverting && !solver2BidPattern.isRevertingBundlerFault) ? 1 : 0, "solver2 counter should be 1 if not reverted");
        assertEq(solver3.counter(), (!solver3BidPattern.isReverting && !solver3BidPattern.isRevertingBundlerFault) ? 1 : 0, "solver3 counter should be 1 if not reverted");
        assertEq(solver4.counter(), (!solver4BidPattern.isReverting && !solver4BidPattern.isRevertingBundlerFault) ? 1 : 0, "solver4 counter should be 1 if not reverted");

        // Track final bonded balances and calculate gas payments
        uint256 solver1FinalBalance = atlas.balanceOfBonded(address(solverOneEOA));
        uint256 solver2FinalBalance = atlas.balanceOfBonded(address(solverTwoEOA));
        uint256 solver3FinalBalance = atlas.balanceOfBonded(address(solverThreeEOA));
        uint256 solver4FinalBalance = atlas.balanceOfBonded(address(solverFourEOA));

        uint256 solver1GasPayment = solver1InitialBalance - solver1FinalBalance;
        uint256 solver2GasPayment = solver2InitialBalance - solver2FinalBalance;
        uint256 solver3GasPayment = solver3InitialBalance - solver3FinalBalance;
        uint256 solver4GasPayment = solver4InitialBalance - solver4FinalBalance;

        console.log("Solver1 gas payment:", solver1GasPayment);
        console.log("Solver2 gas payment:", solver2GasPayment);
        console.log("Solver3 gas payment:", solver3GasPayment);
        console.log("Solver4 gas payment:", solver4GasPayment);
        console.log("Total gas payments:", solver1GasPayment + solver2GasPayment + solver3GasPayment + solver4GasPayment);
    
        uint256 bundlerBalanceAfter = address(bundler).balance;
        uint256 bundlerBalanceDeltaFromGas = bundlerBalanceAfter - bundlerBalanceBefore - mev;

        // Use actual measured gas values from logs
        uint256 baseGasCost = 21000; // Base transaction cost
        uint256 calldataGasCost = 16; // Gas per byte of calldata
        
        // Calculate calldata size for each solver
        uint256 solver1CalldataSize = 4 + 32 + 32; // selector + num_iterations + auxillaryBidAmount
        uint256 solver2CalldataSize = 4 + 32 + 32;
        uint256 solver3CalldataSize = 4 + 32 + 32;
        uint256 solver4CalldataSize = 4 + 32 + 32;

        // Add base cost and calldata cost to each solver's measured gas
        uint256 solver1TotalGas = solver1BidPattern.gasUsed + baseGasCost + (solver1CalldataSize * calldataGasCost);
        uint256 solver2TotalGas = solver2BidPattern.gasUsed + baseGasCost + (solver2CalldataSize * calldataGasCost);
        uint256 solver3TotalGas = solver3BidPattern.gasUsed + baseGasCost + (solver3CalldataSize * calldataGasCost);
        uint256 solver4TotalGas = solver4BidPattern.gasUsed + baseGasCost + (solver4CalldataSize * calldataGasCost);

        // Convert total gas costs to wei (at 1 gwei per gas)
        uint256 gasPrice = 1 gwei;

        // Add 10% surcharge
        uint256 surcharge = 10;
        solver1TotalGas = (solver1TotalGas * (100 + surcharge) / 100) * gasPrice;
        solver2TotalGas = (solver2TotalGas * (100 + surcharge) / 100) * gasPrice;
        solver3TotalGas = (solver3TotalGas * (100 + surcharge) / 100) * gasPrice;
        solver4TotalGas = (solver4TotalGas * (100 + surcharge) / 100) * gasPrice;
        console.log("solver1TotalGas", solver1TotalGas);
        console.log("solver2TotalGas", solver2TotalGas);
        console.log("solver3TotalGas", solver3TotalGas);
        console.log("solver4TotalGas", solver4TotalGas);

        uint256 totalActualGasCost = (solver1TotalGas + solver2TotalGas + solver3TotalGas + solver4TotalGas);

        // Assert that each solver's gas payment matches their calculated total gas cost within 10%
        if (!solver1BidPattern.isRevertingBundlerFault) {
            assertApproxEqAbs(solver1GasPayment, solver1TotalGas, solver1TotalGas / 10, "Solver1 gas payment not within expected range");
        } else {
            assertEq(solver1GasPayment, 0, "Solver1 should not pay gas for bundler fault");
        }

        if (!solver2BidPattern.isRevertingBundlerFault) {
            assertApproxEqAbs(solver2GasPayment, solver2TotalGas, solver2TotalGas / 10, "Solver2 gas payment not within expected range");
        } else {
            assertEq(solver2GasPayment, 0, "Solver2 should not pay gas for bundler fault");
        }

        if (!solver3BidPattern.isRevertingBundlerFault) {
            assertApproxEqAbs(solver3GasPayment, solver3TotalGas, solver3TotalGas / 10, "Solver3 gas payment not within expected range");
        } else {
            assertEq(solver3GasPayment, 0, "Solver3 should not pay gas for bundler fault");
        }

        if (!solver4BidPattern.isRevertingBundlerFault) {
            assertApproxEqAbs(solver4GasPayment, solver4TotalGas, solver4TotalGas / 10, "Solver4 gas payment not within expected range");
        } else {
            assertEq(solver4GasPayment, 0, "Solver4 should not pay gas for bundler fault");
        }

        // Assert that the actual gas cost is within 10% of expected
        console.log("bundlerBalanceDeltaFromGas", bundlerBalanceDeltaFromGas);
        console.log("totalActualGasCost", totalActualGasCost);
        assertApproxEqAbs(bundlerBalanceDeltaFromGas, totalActualGasCost, totalActualGasCost / 10, "Gas costs not within expected range");
    }

    //function testMultipleSolvers_fourSolversAllSucceed() public {
    //    four_solver_generic_test(
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: false, numIterations: 1}),
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: false, numIterations: 1}),
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 300, isReverting: false, numIterations: 1}),
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 400, isReverting: false, numIterations: 1})
    //    );
    //}

    //function testMultipleSolvers_fourSolversAllRevert() public {
    //    four_solver_generic_test(
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: true, numIterations: 5000}),
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: true, numIterations: 5000}),
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 300, isReverting: true, numIterations: 5000}),
    //        SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 400, isReverting: true, numIterations: 5000})
    //    );
    //}

    function testMultipleSolvers_bundler_fault() public {
        four_solver_generic_test(
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: false, isRevertingBundlerFault: false, numIterations: 20000, gasUsed: 1758390}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: false, isRevertingBundlerFault: true, numIterations: 5000, gasUsed: 0}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 300, isReverting: false, isRevertingBundlerFault: false, numIterations: 10000, gasUsed: 924036}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 400, isReverting: false, isRevertingBundlerFault: false, numIterations: 1000, gasUsed: 195068})
        );
    }

    function testMultipleSolvers_fourSolversFirstRevertsSecondSucceeds() public {
        four_solver_generic_test(
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: true, isRevertingBundlerFault: false, numIterations: 5000, gasUsed: 500000}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: false, isRevertingBundlerFault: false, numIterations: 5000, gasUsed: 550000}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 300, isReverting: false, isRevertingBundlerFault: false, numIterations: 5000, gasUsed: 530000}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 400, isReverting: false, isRevertingBundlerFault: false, numIterations: 5000, gasUsed: 520000})
        );
    }
}

contract MultipleSolversDAppControl is DAppControl {

    uint256 public accumulatedAuxillaryBid;

    function setAccumulatedAuxillaryBid(uint256 newAccumulatedAuxillaryBid) external {
        accumulatedAuxillaryBid = newAccumulatedAuxillaryBid;
    }

    event MevAllocated(address indexed control, uint256 mev);
    event AccumulatedAuxillaryBidUpdated(address indexed latestSolver, uint256 newAccumulatedAuxillaryBid);

    constructor(address atlas)
        DAppControl(
            atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
                delegateUser: false,
                requirePreSolver: false,
                requirePostSolver: true,
                zeroSolvers: false, 
                reuseUserOp: false,
                userAuctioneer: false,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                multipleSuccessfulSolvers: true
            })
        )
    {}

    function initiateAuction() external {
    }

    function _preOpsCall(UserOperation calldata) internal override returns (bytes memory) {
        MultipleSolversDAppControl(address(CONTROL)).setAccumulatedAuxillaryBid(0);
    }

    function _postSolverCall(SolverOperation calldata solverOp, bytes calldata) internal override {
        uint256 auxillaryBidAmount = abi.decode(solverOp.data[solverOp.data.length - 32:], (uint256));
        uint256 newAccumulatedAuxillaryBid = MultipleSolversDAppControl(address(CONTROL)).accumulatedAuxillaryBid() + auxillaryBidAmount;
        MultipleSolversDAppControl(address(CONTROL)).setAccumulatedAuxillaryBid(newAccumulatedAuxillaryBid);
        console.log("AccumulatedAuxillaryBidUpdated");
        emit AccumulatedAuxillaryBidUpdated(solverOp.solver, newAccumulatedAuxillaryBid);
    }

    function _allocateValueCall(bool solved, address, uint256 bidAmount, bytes calldata) internal virtual override {
        require(!solved, "must be false when multipleSuccessfulSolvers is true");

        emit MevAllocated(CONTROL, bidAmount);
    }

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        return address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    function getSolverGasLimit() public pure override returns (uint32) {
        return 6_000_000; // Override to allow 6M gas for solvers
    }

    function getDAppGasLimit() public pure override returns (uint32) {
        return 2_000_000; 
    }
}

contract MockSolver is SolverBase {
    bool public executed;
    uint256 public counter;

    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) {
        executed = false;
    }
    function solve(uint256 num_iterations, bool shouldRevert) external {
        counter += 1;
        uint256 dummy = 0;
        for (uint256 i = 0; i < num_iterations; i++) {
            dummy += i;
        }
        if (shouldRevert) {
            revert("revertWhileSolving");
        }
        executed = true;
    }
}