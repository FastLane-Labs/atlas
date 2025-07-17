// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { DAppControl } from "../src/contracts/dapp/DAppControl.sol";
import { UserOperation } from "../src/contracts/types/UserOperation.sol";
import { SolverOperation } from "../src/contracts/types/SolverOperation.sol";
import { DAppOperation } from "../src/contracts/types/DAppOperation.sol";
import { CallConfig } from "../src/contracts/types/ConfigTypes.sol";
import { CallVerification } from "../src/contracts/libraries/CallVerification.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

// Tests for logic in the Atlas.sol contract
contract AtlasTest is BaseTest {
    Sig sig;
    TestDAppControl dappControl;

    function setUp() public override {
        // Run the base setup
        super.setUp();

        vm.startPrank(governanceEOA);
        dappControl = new TestDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(dappControl));
        vm.stopPrank();
    }

    function test_Atlas_BundlerRefundedIfMetacallFails() public {
        UserOperation memory userOp = _buildUserOp();
        DAppOperation memory dAppOp = _buildDAppOp(userOp);

        // Changing UserOp after DAppOp is signed will invalidate the metacall
        userOp.data = new bytes(12345);

        deal(userEOA, 1e18);
        uint256 bundlerBalanceBefore = address(userEOA).balance;

        // User is bundler, sends 1 ETH value with metacall
        vm.startPrank(userEOA);
        bool success = atlas.metacall{value: 1e18}(
            userOp,
            new SolverOperation[](0),
            dAppOp,
            userEOA
        );

        // Metacall should fail, return false instead of reverting, and refund the bundler
        assertEq(success, false, "Metacall should fail");
        assertEq(
            address(userEOA).balance,
            bundlerBalanceBefore,
            "Bundler should be refunded, no balance change"
        );
    }

    // ---------------------------------------------------- //
    //                        Helpers                       //
    // ---------------------------------------------------- //

    function _buildUserOp() internal view returns (UserOperation memory) {
        return UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice,
            nonce: 1,
            deadline: block.timestamp + 2,
            dapp: address(dappControl),
            control: address(dappControl),
            callConfig: dappControl.CALL_CONFIG(),
            dappGasLimit: dappControl.getDAppGasLimit(),
            solverGasLimit: dappControl.getSolverGasLimit(),
            bundlerSurchargeRate: dappControl.getBundlerSurchargeRate(),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });
    }

    function _buildDAppOp(UserOperation memory userOp) internal returns (DAppOperation memory dAppOp) {
        dAppOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            nonce: 1,
            deadline: block.timestamp + 2,
            control: address(dappControl),
            bundler: address(0),
            userOpHash: atlasVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(userOp, new SolverOperation[](0)),
            signature: new bytes(0)
        });
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dAppOp));
        dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
    }
}


contract TestDAppControl is DAppControl {
    constructor(address atlas) DAppControl(
        atlas,
        msg.sender,
        CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
                delegateUser: false,
                requirePreSolver: false,
                requirePostSolver: false,
                zeroSolvers: true,
                reuseUserOp: false, // makes metacall return false instead of revert
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                multipleSuccessfulSolvers: false,
                checkMetacallGasLimit: false
            })) {}

    function _allocateValueCall(
        bool solved,
        address bidToken,
        uint256 bidAmount,
        bytes calldata data
    ) internal virtual override {}

    function getBidFormat(
        UserOperation calldata
    ) public view virtual override returns (address bidToken) {
        return address(0);
    }

    function getBidValue(
        SolverOperation calldata solverOp
    ) public view virtual override returns (uint256) {
        return solverOp.bidAmount;
    }
}