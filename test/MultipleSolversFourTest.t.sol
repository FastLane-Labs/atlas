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
import {ValidCallsResult} from "../src/contracts/types/ValidCalls.sol";
import "../src/contracts/libraries/CallVerification.sol";
import "../src/contracts/interfaces/IAtlas.sol";
import "../src/contracts/libraries/GasAccLib.sol";
import {Result} from "../src/contracts/interfaces/ISimulator.sol";
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
            gas: 3_000_000,
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

        // Build user operation
        UserOperation memory userOp = buildUserOperation(userOpSignerPK);
        (address executionEnvironment, ,) = IAtlas(address(atlas)).getExecutionEnvironment(userOpSigner, address(control));
        bytes32 userOpHash = atlasVerification.getUserOperationHash(userOp);

        // Verify operations will succeed via simulator
        vm.txGasPrice(userOp.maxFeePerGas);
        (bool userOpSimSuccess, Result userOpSimResult, uint256 userOpSimValidCallsResult) = simulator.simUserOperation(userOp);
        assertTrue(userOpSimSuccess, "UserOp simulation failed");
        assertEq(uint8(userOpSimResult), uint8(Result.SimulationPassed), "UserOp simulation result should be SimulationPassed");
        assertEq(userOpSimValidCallsResult, uint256(ValidCallsResult.Valid), "UserOp simulation valid calls result should be Valid");

        // Build solver operation 1
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
        // Estimate gas for solver1
        uint256 solver1MaxWinGas = simulator.estimateMaxSolverWinGasCharge(userOp, solverOp1);
        console.log("Solver1 max win gas:", solver1MaxWinGas);
        
        // Verify simulator calculation
        uint256 solver1CalldataGas = GasAccLib.solverOpCalldataGas(solverOp1.data.length, atlas.L2_GAS_CALCULATOR());
        uint256 solver1ExpectedGas = (solver1CalldataGas + (solverOp1.gas + 21000)) * solverOp1.maxFeePerGas;
        solver1ExpectedGas = solver1ExpectedGas * 120 / 100; // 20% surcharge
        assertApproxEqAbs(solver1MaxWinGas, solver1ExpectedGas, solver1ExpectedGas / 20, "Solver1 gas estimation mismatch");

        // simulate solver1 call
        SolverOperation[] memory solverOps1 = new SolverOperation[](1);
        solverOps1[0] = solverOp1;
        bytes32 callChainHash1 = CallVerification.getCallChainHash(userOp, solverOps1);
        DAppOperation memory dappOp1 = buildDAppOperation(userOpHash, callChainHash1, bundler);
        vm.txGasPrice(userOp.maxFeePerGas);
        (bool solver1CallSuccess, Result solver1CallResult, uint256 solver1SimOutcome) = simulator.simSolverCall(userOp, solverOp1, dappOp1);
        if (solver1BidPattern.isRevertingBundlerFault || solver1BidPattern.isReverting) {
            assertFalse(solver1CallSuccess, "Solver1 call simulation should fail");
        } else {
            assertTrue(solver1CallSuccess, "Solver1 call simulation failed");
            assertEq(uint8(solver1CallResult), uint8(Result.SimulationPassed), "Solver1 call result should be SimulationPassed");
            console.log("Solver1 sim outcome:", solver1SimOutcome);
        }

        // Build solver operation 2
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
        // Estimate gas for solver2
        uint256 solver2MaxWinGas = simulator.estimateMaxSolverWinGasCharge(userOp, solverOp2);
        console.log("Solver2 max win gas:", solver2MaxWinGas);
        
        // Verify simulator calculation
        uint256 solver2CalldataGas = GasAccLib.solverOpCalldataGas(solverOp2.data.length, atlas.L2_GAS_CALCULATOR());
        uint256 solver2ExpectedGas = (solver2CalldataGas + (solverOp2.gas + 21000)) * solverOp2.maxFeePerGas;
        solver2ExpectedGas = solver2ExpectedGas * 120 / 100; // 20% surcharge
        assertApproxEqAbs(solver2MaxWinGas, solver2ExpectedGas, solver2ExpectedGas / 20, "Solver2 gas estimation mismatch");

        // simulate solver2 call
        SolverOperation[] memory solverOps2 = new SolverOperation[](1);
        solverOps2[0] = solverOp2;
        bytes32 callChainHash2 = CallVerification.getCallChainHash(userOp, solverOps2);
        DAppOperation memory dappOp2 = buildDAppOperation(userOpHash, callChainHash2, bundler);
        vm.txGasPrice(userOp.maxFeePerGas);
        (bool solver2CallSuccess, Result solver2CallResult, uint256 solver2SimOutcome) = simulator.simSolverCall(userOp, solverOp2, dappOp2);
        if (solver2BidPattern.isRevertingBundlerFault || solver2BidPattern.isReverting) {
            assertFalse(solver2CallSuccess, "Solver2 call simulation should fail");
        } else {
            assertTrue(solver2CallSuccess, "Solver2 call simulation failed");
            assertEq(uint8(solver2CallResult), uint8(Result.SimulationPassed), "Solver2 call result should be SimulationPassed");
            console.log("Solver2 sim outcome:", solver2SimOutcome);
        }

        // Build solver operation 3
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
        // Estimate gas for solver3
        uint256 solver3MaxWinGas = simulator.estimateMaxSolverWinGasCharge(userOp, solverOp3);
        console.log("Solver3 max win gas:", solver3MaxWinGas);
        
        // Verify simulator calculation
        uint256 solver3CalldataGas = GasAccLib.solverOpCalldataGas(solverOp3.data.length, atlas.L2_GAS_CALCULATOR());
        uint256 solver3ExpectedGas = (solver3CalldataGas + (solverOp3.gas + 21000)) * solverOp3.maxFeePerGas;
        solver3ExpectedGas = solver3ExpectedGas * 120 / 100; // 20% surcharge
        assertApproxEqAbs(solver3MaxWinGas, solver3ExpectedGas, solver3ExpectedGas / 20, "Solver3 gas estimation mismatch");

        // simulate solver3 call
        SolverOperation[] memory solverOps3 = new SolverOperation[](1);
        solverOps3[0] = solverOp3;
        bytes32 callChainHash3 = CallVerification.getCallChainHash(userOp, solverOps3);
        DAppOperation memory dappOp3 = buildDAppOperation(userOpHash, callChainHash3, bundler);
        vm.txGasPrice(userOp.maxFeePerGas);
        (bool solver3CallSuccess, Result solver3CallResult, uint256 solver3SimOutcome) = simulator.simSolverCall(userOp, solverOp3, dappOp3);
        if (solver3BidPattern.isRevertingBundlerFault || solver3BidPattern.isReverting) {
            assertFalse(solver3CallSuccess, "Solver3 call simulation should fail");
        } else {
            assertTrue(solver3CallSuccess, "Solver3 call simulation failed");
            assertEq(uint8(solver3CallResult), uint8(Result.SimulationPassed), "Solver3 call result should be SimulationPassed");
            console.log("Solver3 sim outcome:", solver3SimOutcome);
        }

        // Build solver operation 4
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
        // Estimate gas for solver4
        uint256 solver4MaxWinGas = simulator.estimateMaxSolverWinGasCharge(userOp, solverOp4);
        console.log("Solver4 max win gas:", solver4MaxWinGas);
        
        // Verify simulator calculation
        uint256 solver4CalldataGas = GasAccLib.solverOpCalldataGas(solverOp4.data.length, atlas.L2_GAS_CALCULATOR());
        uint256 solver4ExpectedGas = (solver4CalldataGas + (solverOp4.gas + 21000)) * solverOp4.maxFeePerGas;
        solver4ExpectedGas = solver4ExpectedGas * 120 / 100; // 20% surcharge
        assertApproxEqAbs(solver4MaxWinGas, solver4ExpectedGas, solver4ExpectedGas / 20, "Solver4 gas estimation mismatch");

        // simulate solver4 call
        SolverOperation[] memory solverOps4 = new SolverOperation[](1);
        solverOps4[0] = solverOp4;
        bytes32 callChainHash4 = CallVerification.getCallChainHash(userOp, solverOps4);
        DAppOperation memory dappOp4 = buildDAppOperation(userOpHash, callChainHash4, bundler);
        vm.txGasPrice(userOp.maxFeePerGas);
        (bool solver4CallSuccess, Result solver4CallResult, uint256 solver4SimOutcome) = simulator.simSolverCall(userOp, solverOp4, dappOp4);
        if (solver4BidPattern.isRevertingBundlerFault || solver4BidPattern.isReverting) {
            assertFalse(solver4CallSuccess, "Solver4 call simulation should fail");
        } else {
            assertTrue(solver4CallSuccess, "Solver4 call simulation failed");
            assertEq(uint8(solver4CallResult), uint8(Result.SimulationPassed), "Solver4 call result should be SimulationPassed");
            console.log("Solver4 sim outcome:", solver4SimOutcome);
        }
        
        // Build solver ops
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

        // Calculate total gas for each solver using the same formula as simulator
        uint256 solver1TotalGas = (solver1CalldataGas + (solver1BidPattern.gasUsed + 21000)) * solverOp1.maxFeePerGas;
        uint256 solver2TotalGas = (solver2CalldataGas + (solver2BidPattern.gasUsed + 21000)) * solverOp2.maxFeePerGas;
        uint256 solver3TotalGas = (solver3CalldataGas + (solver3BidPattern.gasUsed + 21000)) * solverOp3.maxFeePerGas;
        uint256 solver4TotalGas = (solver4CalldataGas + (solver4BidPattern.gasUsed + 21000)) * solverOp4.maxFeePerGas;

        // Add 20% surcharge
        uint256 surcharge = 20;
        solver1TotalGas = solver1TotalGas * (100 + surcharge) / 100;
        solver2TotalGas = solver2TotalGas * (100 + surcharge) / 100;
        solver3TotalGas = solver3TotalGas * (100 + surcharge) / 100;
        solver4TotalGas = solver4TotalGas * (100 + surcharge) / 100;

        console.log("solver1TotalGas", solver1TotalGas);
        console.log("solver2TotalGas", solver2TotalGas);
        console.log("solver3TotalGas", solver3TotalGas);
        console.log("solver4TotalGas", solver4TotalGas);

        uint256 totalActualGasCost = (solver1TotalGas + solver2TotalGas + solver3TotalGas + solver4TotalGas);

        // Assert that each solver's gas payment matches their calculated total gas cost within 20%
        if (!solver1BidPattern.isRevertingBundlerFault) {
            assertApproxEqRel(solver1GasPayment, solver1TotalGas, 0.1e18, "Solver1 gas payment not within expected range");
        } else {
            assertEq(solver1GasPayment, 0, "Solver1 should not pay gas for bundler fault");
        }

        if (!solver2BidPattern.isRevertingBundlerFault) {
            assertApproxEqRel(solver2GasPayment, solver2TotalGas, 0.1e18, "Solver2 gas payment not within expected range");
        } else {
            assertEq(solver2GasPayment, 0, "Solver2 should not pay gas for bundler fault");
        }

        if (!solver3BidPattern.isRevertingBundlerFault) {
            assertApproxEqRel(solver3GasPayment, solver3TotalGas, 0.1e18, "Solver3 gas payment not within expected range");
        } else {
            assertEq(solver3GasPayment, 0, "Solver3 should not pay gas for bundler fault");
        }

        console.log("solver4GasPayment", solver4GasPayment);
        console.log("solver4TotalGas", solver4TotalGas);

        if (!solver4BidPattern.isRevertingBundlerFault) {
            assertApproxEqRel(solver4GasPayment, solver4TotalGas, 0.1e18, "Solver4 gas payment not within expected range");
        } else {
            assertEq(solver4GasPayment, 0, "Solver4 should not pay gas for bundler fault");
        }

        // Assert that the actual gas cost is within 20% of expected
        console.log("bundlerBalanceDeltaFromGas", bundlerBalanceDeltaFromGas);
        console.log("totalActualGasCost", totalActualGasCost);
        assertApproxEqRel(bundlerBalanceDeltaFromGas, totalActualGasCost, 0.2e18, "Gas costs not within expected range");
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
        return bytes("");
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