// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";
import { BaseTest } from "./base/BaseTest.t.sol";
import { ArbitrageTest } from "./base/ArbitrageTest.t.sol";
import { SolverBase } from "src/contracts/solver/SolverBase.sol";
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { SolverOutcome } from "src/contracts/types/EscrowTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { DAppOperation } from "src/contracts/types/DAppApprovalTypes.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";

interface IWETH {
    function withdraw(uint256 wad) external;
}

contract FlashLoanTest is BaseTest {
    DummyDAppControlBuilder public control;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    Sig public sig;

    function setUp() public virtual override {
        BaseTest.setUp();

        // Creating new gov address (SignatoryActive error if already registered with control)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        // Deploy
        vm.startPrank(governanceEOA);

        control = new DummyDAppControlBuilder(address(atlas), WETH_ADDRESS);
        atlasVerification.initializeGovernance(address(control));
        vm.stopPrank();
    }

    function testFlashLoan() public {
        vm.startPrank(solverOneEOA);
        SimpleSolver solver = new SimpleSolver(WETH_ADDRESS, address(atlas));
        deal(WETH_ADDRESS, address(solver), 1e18); // 1 WETH to solver to pay bid
        atlas.bond(1 ether); // gas for solver to pay
        vm.stopPrank();

        vm.startPrank(userEOA);
        deal(userEOA, 100e18); // eth to solver for atleth deposit
        atlas.deposit{ value: 100e18 }();
        vm.stopPrank();

        // Input params for Atlas.metacall() - will be populated below

        UserOperation memory userOp = new UserOperationBuilder()
            .withFrom(userEOA)
            .withTo(address(atlas))
            .withGas(1_000_000)
            .withMaxFeePerGas(tx.gasprice + 1)
            .withNonce(address(atlasVerification))
            .withDapp(address(control))
            .withControl(address(control))
            .withCallConfig(control.CALL_CONFIG())
            .withDeadline(block.number + 2)
            .withData(new bytes(0))
            .build();

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withSolver(address(solver))
            .withControl(address(control))
            .withUserOpHash(userOp)
            .withBidToken(userOp)
            .withBidAmount(1e18)
            .withData(abi.encodeWithSelector(SimpleSolver.noPayback.selector))
            .withValue(10e18)
            .sign(address(atlasVerification), solverOnePK)
            .build();

        // Solver signs the solverOp
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Frontend creates dAppOp calldata after seeing rest of data
        DAppOperation memory dAppOp = new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(address(control))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK)
            .build();

        // Frontend signs the dAppOp payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // make the actual atlas call that should revert
        vm.startPrank(userEOA);
        vm.expectEmit(true, true, true, true);
        uint256 result = (1 << uint256(SolverOutcome.BidNotPaid));
        emit AtlasEvents.SolverTxResult(address(solver), solverOneEOA, true, false, result);
        vm.expectRevert();
        atlas.metacall({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();

        // now try it again with a valid solverOp - but dont fully pay back
        solverOps[0] = new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withSolver(address(solver))
            .withControl(address(control))
            .withUserOpHash(userOp)
            .withBidToken(userOp)
            .withBidAmount(1e18)
            .withData(abi.encodeWithSelector(SimpleSolver.onlyPayBid.selector, 1e18))
            .withValue(address(atlas).balance + 1)
            .sign(address(atlasVerification), solverOnePK)
            .build();

        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        dAppOp = new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(address(control))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK)
            .build();
            
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Call again with partial payback, should still revert
        vm.startPrank(userEOA);
        vm.expectEmit(true, true, true, true);
        result = (1 << uint256(SolverOutcome.CallValueTooHigh));
        console.log("result", result);
        emit AtlasEvents.SolverTxResult(address(solver), solverOneEOA, false, false, result);
        vm.expectRevert();
        atlas.metacall({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();

        // final try, should be successful with full payback
        solverOps[0] = new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withSolver(address(solver))
            .withControl(address(control))
            .withUserOpHash(userOp)
            .withBidToken(userOp)
            .withBidAmount(1e18)
            .withData(abi.encodeWithSelector(SimpleSolver.payback.selector, 1e18))
            .withValue(10e18)
            .sign(address(atlasVerification), solverOnePK)
            .build();

        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOps[0]));
        solverOps[0].signature = abi.encodePacked(sig.r, sig.s, sig.v);

        dAppOp = new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(address(control))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK)
            .build();

        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        uint256 solverStartingWETH = WETH.balanceOf(address(solver));
        uint256 atlasStartingETH = address(atlas).balance;
        uint256 userStartingETH = address(userEOA).balance;

        assertEq(solverStartingWETH, 1e18, "solver incorrect starting WETH");
        assertEq(atlasStartingETH, 102e18, "atlas incorrect starting ETH"); // 2e initial + 1e solver + 100e user deposit

        // Last call - should succeed
        vm.startPrank(userEOA);
        result = 0;
        vm.expectEmit(true, true, true, true);
        emit AtlasEvents.SolverTxResult(address(solver), solverOneEOA, true, true, result);
        atlas.metacall({ userOp: userOp, solverOps: solverOps, dAppOp: dAppOp });
        vm.stopPrank();

        uint256 solverEndingWETH = WETH.balanceOf(address(solver));
        uint256 atlasEndingETH = address(atlas).balance;
        uint256 userEndingETH = address(userEOA).balance;

        // atlas 2e beginning bal + 1e from solver +100e eth from user = 103e atlas total
        // after metacall 1e user payout + 0.0001e bundler(user) gas refund = 101.9999e after metacall

        console.log("solverWETH", solverStartingWETH, solverEndingWETH);
        console.log("solveratlETH", atlas.balanceOf(solverOneEOA));
        console.log("atlasETH", atlasStartingETH, atlasEndingETH);
        console.log("userETH", userStartingETH, userEndingETH);

        assertEq(solverEndingWETH, 0, "solver WETH not used");
        assertEq(atlas.balanceOf(solverOneEOA), 0, "solver atlETH not used");
        assertTrue(atlasEndingETH < atlasStartingETH, "atlas incorrect ending ETH"); // atlas should lose a bit of eth used for gas refund
        assertTrue((userEndingETH - userStartingETH) > 1 ether, "user incorrect ending ETH"); // user bal should increase by more than 1e (bid + gas refund)
    }
}

contract DummyDAppControlBuilder is DAppControl {
    address immutable weth;

    constructor(
        address _atlas,
        address _weth
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
                delegateUser: true,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: true,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: true,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false
            })
        )
    {
        weth = _weth;
    }

    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata) internal override {
        if (bidToken != address(0)) {
            revert("not supported");
        }
        
        SafeTransferLib.safeTransferETH(_user(), address(this).balance);
    }

    function getBidFormat(UserOperation calldata) public view override returns (address bidToken) {
        bidToken = address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    fallback() external { }
}

contract SimpleSolver {
    address weth;
    address msgSender;
    address atlas;

    constructor(address _weth, address _atlas) {
        weth = _weth;
        atlas = _atlas;
    }

    function atlasSolverCall(
        address sender,
        address bidToken,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata extraReturnData
    )
        external
        payable
        returns (bool success, bytes memory data)
    {
        msgSender = msg.sender;
        (success, data) = address(this).call{ value: msg.value }(solverOpData);

        if (bytes4(solverOpData[:4]) == SimpleSolver.payback.selector) {
            uint256 shortfall = IEscrow(atlas).shortfall();

            if (shortfall < msg.value) shortfall = 0;
            else shortfall -= msg.value;

            IEscrow(atlas).reconcile{ value: msg.value }(msg.sender, sender, shortfall);
        }
    }

    function noPayback() external payable {
        address(0).call{ value: msg.value }(""); // do something with the eth and dont pay it back
    }

    function onlyPayBid(uint256 bidAmount) external payable {
        IWETH(weth).withdraw(bidAmount);
        payable(msgSender).transfer(bidAmount); // pay back to atlas
        address(0).call{ value: msg.value }(""); // do something with the remaining eth
    }

    function payback(uint256 bidAmount) external payable {
        IWETH(weth).withdraw(bidAmount);
        payable(msgSender).transfer(bidAmount); // pay back to atlas
    }

    receive() external payable { }
}
