// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";
import { DAppConfig, DAppOperation } from "../src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "../src/contracts/types/ValidCallsTypes.sol";
import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";
import { BaseTest } from "./base/BaseTest.t.sol";
import { SimpleRFQSolver } from "./SwapIntent.t.sol";


contract AtlasVerificationTest is BaseTest {
    TxBuilder txBuilder;
    DummyDAppControl dAppControl;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);

        // Deploy new DummyDAppControl Controller from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        dAppControl = new DummyDAppControl(address(atlas), governanceEOA);
        atlasVerification.initializeGovernance(address(dAppControl));
        atlasVerification.integrateDApp(address(dAppControl));
        vm.stopPrank();

        txBuilder = new TxBuilder({
            controller: address(dAppControl),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });
    }

    function test_T() public {
        // Create atlas metacall transaction
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number + 2,
            ""
        );

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        SolverOperation memory solverOp = txBuilder.buildSolverOperation(
            userOp,
            "",
            solverOneEOA,
            address(0),
            1e18
        );

        // Solver signs the solverOp
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;

        DAppOperation memory dappOp = txBuilder.buildDAppOperation(
            governanceEOA,
            userOp,
            solverOps
        );

        // Frontend signs the dAppOp payload
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        uint256 msgValue = 0;
        address msgSender = userEOA;
        bool isSimulation = false;

        vm.expectRevert(abi.encodeWithSelector(AtlasVerification.InvalidCaller.selector));
        
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, msgValue, msgSender, isSimulation);

        vm.startPrank(address(atlas));

        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, msgValue, msgSender, isSimulation);

        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Success");
    }

}
