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
/// @dev this test is used to illustrate and test the multiple successful solvers feature
/// @dev MultipleSolversDAppControl serves as both the dapp and dAppControl contracts
/// @dev It tracks an "accumulatedAuxillaryBid" which is the sum of all auxillary bids from all solvers
/// @dev and emits an event when updated. These events (and their order) are used to check that solvers have
/// @dev been executed as expected in various scenarios.
/// @dev Solvers also include an auxillary bid with their call, which is just a number (not paid) tracked by the dapp
/// @dev control contract.

contract MultipleSolversTest is BaseTest, AtlasErrors {
    MultipleSolversDAppControl control;
    MockSolver solver1;
    MockSolver solver2;

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
        bool isReverting
    ) internal view returns (SolverOperation memory) {
        bytes memory data;
        if (isReverting) {
            data = abi.encodeWithSelector(solver1.revertWhileSolving.selector);
        } else {
            data = abi.encodeWithSelector(solver1.solve.selector);
            data = abi.encodeWithSelector(solver1.solve.selector, auxillaryBidAmount);
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
    }

    function two_solver_generic_test(
        SolverBidPattern memory solver1BidPattern,
        SolverBidPattern memory solver2BidPattern
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
            solver1BidPattern.isReverting
        );
        SolverOperation memory solverOp2 = buildSolverOperation(
            solverTwoPK,
            address(solver2),
            userOpHash,
            solver2BidPattern.bidAmount,
            solver2BidPattern.auxillaryBidAmount,
            solver2BidPattern.isReverting
        );
        SolverOperation[] memory solverOps = new SolverOperation[](2);
        solverOps[0] = solverOp1;
        solverOps[1] = solverOp2;

        bytes32 callChainHash = CallVerification.getCallChainHash(userOp, solverOps);
        DAppOperation memory dappOp = buildDAppOperation(userOpHash, callChainHash, bundler);

        uint256 solverOneResult = solver1BidPattern.isReverting ? (1 << uint256(SolverOutcome.SolverOpReverted)) : (1 << uint256(SolverOutcome.MultipleSolvers));
        uint256 solverTwoResult = solver2BidPattern.isReverting ? (1 << uint256(SolverOutcome.SolverOpReverted)) : (1 << uint256(SolverOutcome.MultipleSolvers));
        
        uint256 mev = 0;
        if (!solver1BidPattern.isReverting) {
            mev += solver1BidPattern.bidAmount;
        }
        if (!solver2BidPattern.isReverting) {
            mev += solver2BidPattern.bidAmount;
        }

        uint256 accumulatedAuxillaryBidSolverOne = solver1BidPattern.isReverting ? 0 : solver1BidPattern.auxillaryBidAmount;
        uint256 accumulatedAuxillaryBidSolverTwo = accumulatedAuxillaryBidSolverOne;
        accumulatedAuxillaryBidSolverTwo += solver2BidPattern.isReverting ? 0 : solver2BidPattern.auxillaryBidAmount;

        uint256 metacallGasLimit = simulator.estimateMetacallGasLimit(userOp, solverOps);

        vm.deal(address(bundler), 2 ether);
        vm.txGasPrice(1 gwei);

        if (!solver1BidPattern.isReverting) {
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
            true,
            !solver1BidPattern.isReverting,
            solverOneResult
        );
        if (!solver2BidPattern.isReverting) {
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
            true,
            !solver2BidPattern.isReverting,
            solverTwoResult
        );
        vm.expectEmit(address(executionEnvironment));
        emit MultipleSolversDAppControl.MevAllocated(
            address(control), 
            mev
        );

        uint256 bundlerBalanceBefore = address(bundler).balance;

        vm.startPrank(bundler);
        (bool success, bytes memory returnData) = address(atlas).call{gas: metacallGasLimit}(
            abi.encodeWithSelector(atlas.metacall.selector, userOp, solverOps, dappOp, address(0))
        );
        assertEq(success, true);
        assertEq(abi.decode(returnData, (bool)), false); // auctionWon should be false

        vm.stopPrank();

        uint256 bundlerBalanceAfter = address(bundler).balance;
        uint256 bundlerBalanceDeltaFromGas = bundlerBalanceAfter - bundlerBalanceBefore - mev;

        // Compute the gas cost of the transaction.
        // Note: txGasUsed is expected to be 1.6 mill 
        // At 1 gwei per gas, the cost is txGasUsed * 1e9 wei.
        uint256 txGasCost = 1600000 * 1e9;

        assertGt(bundlerBalanceDeltaFromGas, 1300000000000000, "bundler did not recoup > 80% of gas costs");
    }

    function testMultipleSolvers_twoSolversBothSucceed() public {
        two_solver_generic_test(
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: false}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: false})
        );
    }

    function testMultipleSolvers_twoSolversBothRevert() public {
        two_solver_generic_test(
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: true}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: true})
        );
    }

    function testMultipleSolvers_twoSolversFirstSucceedsSecondReverts() public {
        two_solver_generic_test(
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: false}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: true})
        );
    }

    function testMultipleSolvers_twoSolversFirstRevertsSecondSucceeds() public {
        two_solver_generic_test(
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 100, isReverting: true}),
            SolverBidPattern({bidAmount: 1 ether, auxillaryBidAmount: 200, isReverting: false})
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
        uint256 auxillaryBidAmount = abi.decode(solverOp.data[4:], (uint256));
        uint256 newAccumulatedAuxillaryBid = MultipleSolversDAppControl(address(CONTROL)).accumulatedAuxillaryBid() + auxillaryBidAmount;
        MultipleSolversDAppControl(address(CONTROL)).setAccumulatedAuxillaryBid(newAccumulatedAuxillaryBid);

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
}

contract MockSolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) {}
    function solve() external view {
        uint256 dummy = 0;
        // Adjust loop iterations to achieve the desired extra gas consumption.
        for (uint256 i = 0; i < 5_000; i++) {
            dummy += i;
        }
    }

    function revertWhileSolving() external pure {
        uint256 dummy = 0;
        // Adjust loop iterations to achieve the desired extra gas consumption.
        for (uint256 i = 0; i < 5_000; i++) {
            dummy += i;
        }
        revert("revertWhileSolving");
    }
}