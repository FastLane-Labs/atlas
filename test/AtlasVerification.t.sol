// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";
import { DAppConfig, DAppOperation, CallConfig } from "../src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "../src/contracts/types/ValidCallsTypes.sol";
import { TxBuilder } from "../src/contracts/helpers/TxBuilder.sol";
import { DummyDAppControl, CallConfigBuilder } from "./base/DummyDAppControl.sol";
import { AtlasBaseTest } from "./base/AtlasBaseTest.t.sol";
import { SimpleRFQSolver } from "./SwapIntent.t.sol";
import { CallVerification } from "../../src/contracts/libraries/CallVerification.sol";
import { CallBits } from "../src/contracts/libraries/CallBits.sol";


contract AtlasVerificationTest is AtlasBaseTest {
    TxBuilder txBuilder;
    DummyDAppControl dAppControl;
    CallConfig callConfig;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        // we reset the callConfig to all false for each test
        // this allows us to selectively enable flags for each test.
        // we then need to call refreshGlobals() to rebuild the
        // dAppControl and txBuilder in the test itself. not every test
        // needs to do this, so we try handle the most common case here.
        callConfig = CallConfigBuilder.allFalseCallConfig();
        refreshGlobals();
    }

    function refreshGlobals() public {
        AtlasBaseTest.setUp();
        dAppControl = buildDummyDAppControl();
        txBuilder = buildTxBuilder();
    }

    function buildDummyDAppControl() public returns (DummyDAppControl) {
        // Deploy new DummyDAppControl Controller from new gov and initialize in Atlas
        vm.startPrank(governanceEOA);
        DummyDAppControl control = new DummyDAppControl(address(atlas), governanceEOA, callConfig);
        atlasVerification.initializeGovernance(address(control));
        atlasVerification.integrateDApp(address(control));
        vm.stopPrank();

        return control;
    }

    function buildTxBuilder() public returns (TxBuilder) {
        TxBuilder builder = new TxBuilder({
            controller: address(dAppControl),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });

        return builder;
    }

    function buildUserOperation() public view returns (UserOperation memory) {
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number + 2,
            ""
        );

        // User signs the userOp
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        return userOp;
    }

    function buildSolverOperation(UserOperation memory userOp) public view returns (SolverOperation memory) {
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

        return solverOp;
    }

    function buildSolverOperations(UserOperation memory userOp) public view returns (SolverOperation[] memory) {
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = buildSolverOperation(userOp);
        return solverOps;
    }

    function buildDAppOperation(UserOperation memory userOp, SolverOperation[] memory solverOps) public view returns (DAppOperation memory) {
        DAppOperation memory dappOp = txBuilder.buildDAppOperation(
            governanceEOA,
            userOp,
            solverOps
        );

        // Frontend signs the dAppOp payload
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        return dappOp;
    }

    //
    // ---- TESTS BEGIN HERE ---- //
    //

    // Valid cases

    // 
    // given a valid atlas transaction
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_ValidResult() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // InvalidCaller cases

    //
    // given an otherwise valid atlas transaction where the caller is not the atlas contract
    // when validCalls is called
    // then it should return InvalidCaller
    //
    function test_validCalls_InvalidCallerResult() public {
        // given an otherwise valid atlas transaction where the caller is not the atlas contract
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // then it should return InvalidCaller
        vm.expectRevert(AtlasVerification.InvalidCaller.selector);
        
        // when validCalls is called
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);
    }

    //
    // InvalidAuctioneer cases
    //
    
    // 
    // given a valid atlas transaction
    //   and a callConfig with verifyCallChainHash = true
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_VerifyCallChainHash_Valid() public {
        // given a valid atlas transaction
        //   and a callConfig with verifyCallChainHash = true
        callConfig.verifyCallChainHash = true;
        refreshGlobals();

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an atlas transaction with an invalid callChainHash
    //   and a callConfig with verifyCallChainHash = true
    // when validCalls is called
    // then it should return InvalidAuctioneer
    //
    function test_validCalls_VerifyCallChainHash_InvalidAuctioneer() public {
        // given an atlas transaction with an invalid callChainHash
        //   and a callConfig with verifyCallChainHash = true
        callConfig.verifyCallChainHash = true;
        refreshGlobals();

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);

        DAppOperation memory dappOp = txBuilder.buildDAppOperation(
            governanceEOA,
            userOp,
            solverOps
        );
        dappOp.callChainHash = bytes32(0); // break the callChainHash

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));

        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return InvalidAuctioneer
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.InvalidAuctioneer, "validCallsResult should be InvalidAuctioneer");
    }

    //
    // given an atlas transaction with an invalid callChainHash
    //   and a callConfig with verifyCallChainHash = true
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_Simulated_VerifyCallChainHash_Valid() public {
        // given an atlas transaction with an invalid callChainHash
        //   and a callConfig with verifyCallChainHash = true
        callConfig.verifyCallChainHash = true;
        refreshGlobals();

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);

        DAppOperation memory dappOp = txBuilder.buildDAppOperation(
            governanceEOA,
            userOp,
            solverOps
        );
        dappOp.callChainHash = bytes32(0); // break the callChainHash

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called with isSimulation = true
        vm.startPrank(address(atlas));

        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // DAppSignatureInvalid cases

    //
    // given an otherwise valid atlas transaction with an invalid dAppOp signature
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    // 
    function test_validCalls_BrokenSignature_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with an invalid dAppOp signature
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);
        dappOp.signature = bytes("");

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with an invalid dAppOp signature
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_Simulated_BrokenSignature_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with an invalid dAppOp signature
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);
        dappOp.signature = bytes("");

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called with isSimulation = true
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // TODO: tests for _verifyAuctioneer where (true, true) is returned

    // cases that cause bypassSignatoryApproval
    // * dConfig.callConfig.allowsUserAuctioneer() && dAppOp.from == userOp.sessionKey -> user is auctioneer
    // * dConfig.callConfig.allowsSolverAuctioneer() && dAppOp.from == solverOps[0].from -> solver is auctioneer
    // * dConfig.callConfig.allowsUnknownAuctioneer() -> unknown auctioneer

    // 
    // given a valid atlas transaction with a disabled signatory and user is auctioneer
    //  - user is auctioneer
    //  - solver is auctioneer
    //  - unknown auctioneer
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SignerNotEnabled_BypassSignatory_UserAuctioneer_Valid() public {
        // given a valid atlas transaction with a disabled signatory and user is auctioneer
        callConfig.userAuctioneer = true;
        refreshGlobals();
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = buildUserOperation();
        userOp.sessionKey = governanceEOA;
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // 
    // given a valid atlas transaction with a disabled signatory and solver is auctioneer
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SignerNotEnabled_BypassSignatory_SolverAuctioneer_Valid() public {
        // given a valid atlas transaction with a disabled signatory and user is auctioneer
        callConfig.solverAuctioneer = true;
        refreshGlobals();
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = txBuilder.buildDAppOperation(
            solverOneEOA,
            userOp,
            solverOps
        );

        // Frontend signs the dAppOp payload
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, solverOneEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // 
    // given a valid atlas transaction with a disabled signatory and unknown auctioneer
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SignerNotEnabled_BypassSignatory_UnknownAuctioneer_Valid() public {
        // given a valid atlas transaction with a disabled signatory and user is auctioneer
        callConfig.unknownAuctioneer = true;
        refreshGlobals();
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction where the signer is not enabled by the dApp
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SignerNotEnabled_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction where the signer is not enabled by the dApp
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction where the control address doesn't match the dApp config.to
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_ControlConfigMismatch_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction where the control address doesn't match the dApp config.to
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: atlasVerification.getNextNonce(governanceEOA),
            deadline: userOp.deadline,
            control: address(0),
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given a valid atlas transaction
    //   and a dConfig.to that is not a contract
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction dAppOp.nonce greater than uint128.max - 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    // TODO: this test is failing, but I don't think it should be. Need to investigate.
    function test_validCalls_NonceTooLarge_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction dAppOp.nonce greater than uint128.max - 1
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        uint256 nonce = type(uint128).max;
        // currently it doesn't seem to like any nonce above getNextNonce, indicating that config.sequence is not being respected
        // uint256 nonce = atlasVerification.getNextNonce(governanceEOA)+1;
        // console.log("nonce: ", nonce);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: nonce,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 0
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_NonceIsZero_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 0
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 0,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 0
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_NonceIsZero_Simulated_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 0
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 0,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 1
    //   and the callConfig.sequenced = false
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_UnsequencedNonceIsOne_Valid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 1
        //   and the callConfig.sequenced = false
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 1,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // TODO: tests to do with the nonce bitmap stuff, no idea what is going on in there yet

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 1
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SequencedNonceIsOne_Valid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 1
        //   and the callConfig.sequenced = true
        //   and the nonce is uninitialized for the user
        callConfig.sequenced = true;
        refreshGlobals();
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 1,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SequencedNonceIsTwo_Valid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
        //   and the callConfig.sequenced = true
        //   and the nonce is uninitialized for the user
        callConfig.sequenced = true;
        refreshGlobals();
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 2,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the last dAppOp.nonce for the user is 1
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SequencedNonceWasOneIsNowTwo_Valid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
        //   and the callConfig.sequenced = true
        //   and the last dAppOp.nonce for the user is 1
        callConfig.sequenced = true;
        refreshGlobals();

        // these first ops are to increment the nonce to 1
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        userOp = buildUserOperation();
        config = dAppControl.getDAppConfig(userOp);
        solverOps = buildSolverOperations(userOp);
        dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 2,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 3
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SequencedNonceWasOneIsNowThree_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with a dAppOp.nonce of 3
        //   and the callConfig.sequenced = true
        //   and the last dAppOp.nonce for the user is 1
        callConfig.sequenced = true;
        refreshGlobals();

        // these first ops are to increment the nonce to 1
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        userOp = buildUserOperation();
        config = dAppControl.getDAppConfig(userOp);
        solverOps = buildSolverOperations(userOp);
        dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: 3,
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(config, userOp, solverOps),
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    // UserSignatureInvalid cases

    // userOp signatures are invalid when:
    // * (userOp.signature.length == 0)
    // * _hashTypedDataV4(_getProofHash(userOp)).recover(userOp.signature) != userOp.from

    //
    // given an otherwise valid atlas transaction with a blank userOp signature
    //   and the bundler is not the user
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //
    function test_validCalls_InvalidUserSignatureBlank_BundlerNotUser_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction with an invalid userOp signature
        //   and the bundler is not the user
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number + 2,
            ""
        );

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return UserSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.UserSignatureInvalid, "validCallsResult should be UserSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp signature signed by someone else
    //   and the bundler is not the user
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //
    function test_validCalls_InvalidUserSignatureWrongEOA_BundlerNotUser_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction with an invalid userOp signature
        //   and the bundler is not the user
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number + 2,
            ""
        );

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(123, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return UserSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.UserSignatureInvalid, "validCallsResult should be UserSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a blank userOp signature
    //   and the bundler is the user
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_InvalidUserSignatureBlank_BundlerIsUser_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction with an invalid userOp signature
        //   and the bundler is the user
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number + 2,
            ""
        );

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a blank userOp signature
    //  and the bundler is the dapp
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_InvalidUserSignatureBlank_Simulated_Valid() public {
        // given an otherwise valid atlas transaction with a blank userOp signature
        //   and the bundler is the user
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number + 2,
            ""
        );

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction where userOp.control != dConfig.to
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //
    function test_validCalls_InvalidUserOpControl_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction where userOp.control != dConfig.to
        //   and the bundler is not the user
        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: atlasVerification.getNextNonce(userEOA),
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(0),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);

        DAppConfig memory config = DAppConfig({ to: address(dAppControl), callConfig: CallBits.encodeCallConfig(callConfig), bidToken: address(0) });
        bytes32 callChainHash = CallVerification.getCallChainHash(config, userOp, solverOps);
        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: atlasVerification.getNextNonce(governanceEOA),
            deadline: userOp.deadline,
            control: address(dAppControl),
            bundler: address(0),
            userOpHash: CallVerification.getUserOperationHash(userOp),
            callChainHash: callChainHash,
            signature: new bytes(0)
        });

        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return UserSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.UserSignatureInvalid, "validCallsResult should be UserSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction userOp.nonce greater than uint128.max - 1
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //
    function test_validCalls_UserOpNonceToBig_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction userOp.nonce greater than uint128.max - 1
        //   and the bundler is the user
        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: type(uint128).max,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return UserSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.UserSignatureInvalid, "validCallsResult should be UserSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 0
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //
    function test_validCalls_UserOpNonceIsZero_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction userOp.nonce greater than uint128.max - 1
        //   and the bundler is the user
        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 0,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return UserSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.UserSignatureInvalid, "validCallsResult should be UserSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 0
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_UserOpNonceIsZero_Simulated_Valid() public {
        // given an otherwise valid atlas transaction userOp.nonce greater than uint128.max - 1
        //   and the bundler is the user
        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 0,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 1
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_UserOpNonceIsOne_UserSignatureInvalid() public {
        // given an otherwise valid atlas transaction with a userOp.nonce of 1
        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 1,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    // TODO: test to do with the nonce bitmap stuff, nfi what its doing

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 1
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SequencedUserOpNonceIsOne_Valid() public {
        // given an otherwise valid atlas transaction with a userOp.nonce of 1
        //   and the callConfig.sequenced = true
        //   and the nonce is uninitialized for the user
        callConfig.sequenced = true;
        refreshGlobals();

        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 1,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SequencedUserOpNonceIsTwo_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with a userOp.nonce of 1
        //   and the callConfig.sequenced = true
        //   and the nonce is uninitialized for the user
        callConfig.sequenced = true;
        refreshGlobals();

        UserOperation memory userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 2,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SequencedUserOpNonceIsTwo_Valid() public {
        // given an otherwise valid atlas transaction with a userOp.nonce of 2
        //   and the callConfig.sequenced = true
        //   and the last nonce for the user is 1
        callConfig.sequenced = true;
        refreshGlobals();

        // these first ops are to increment the nonce to 1
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then the actual tx
        userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 2,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps = buildSolverOperations(userOp);
        dappOp = buildDAppOperation(userOp, solverOps);

        config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 3
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SequencedUserOpNonceIsThree_DAppSignatureInvalid() public {
        // given an otherwise valid atlas transaction with a userOp.nonce of 3
        //   and the callConfig.sequenced = true
        //   and the last nonce for the user is 1
        callConfig.sequenced = true;
        refreshGlobals();

        // these first ops are to increment the nonce to 1
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then the actual tx
        userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            nonce: 3,
            deadline: block.number + 2,
            dapp: address(dAppControl),
            control: address(dAppControl),
            sessionKey: address(0),
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps = buildSolverOperations(userOp);
        dappOp = buildDAppOperation(userOp, solverOps);

        config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, governanceEOA, false);

        // then it should return DAppSignatureInvalid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppSignatureInvalid, "validCallsResult should be DAppSignatureInvalid");
    }

    // TooManySolverOps cases

    //
    // given an otherwise valid atlas transaction with more than (type(uint8).max - 2) = 253 solverOps
    // when validCalls is called
    // then it should return TooManySolverOps
    //
    function test_validCalls_TooManySolverOps() public {
        // given an otherwise valid atlas transaction with more than (type(uint8).max - 2) = 253 solverOps
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](255);
        for (uint i = 0; i < 255; i++) {
            solverOps[i] = buildSolverOperation(userOp);
        }
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return TooManySolverOps
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.TooManySolverOps, "validCallsResult should be TooManySolverOps");
    }

    // UserDeadlineReached cases

    //
    // given an otherwise valid atlas transaction with a userOp.deadline earlier than block.number
    // when validCalls is called
    // then it should return UserDeadlineReached
    //
    function test_validCalls_UserDeadlineReached() public {
        // given a valid atlas transaction
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            0,
            block.number -1,
            ""
        );

        // User signs the userOp
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return UserDeadlineReached
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.UserDeadlineReached, "validCallsResult should be UserDeadlineReached");
    }

    // DAppDeadlineReached cases

    //
    // given an otherwise valid atlas transaction with a dAppOp.deadline earlier than block.number
    // when validCalls is called
    // then it should return DAppDeadlineReached
    //
    function test_validCalls_DAppDeadlineReached() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);

        bytes32 userOpHash = CallVerification.getUserOperationHash(userOp);
        bytes32 callChainHash = CallVerification.getCallChainHash(config, userOp, solverOps);

        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: atlasVerification.getNextNonce(governanceEOA),
            deadline: block.number - 1,
            control: userOp.control,
            bundler: address(0),
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return DAppDeadlineReached
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.DAppDeadlineReached, "validCallsResult should be DAppDeadlineReached");
    }

    // InvalidBundler cases

    //
    // given an otherwise valid atlas transaction where the bundler is not the message sender
    // when validCalls is called
    // then it should return InvalidBundler
    //
    function test_validCalls_InvalidBundler() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);

        bytes32 userOpHash = CallVerification.getUserOperationHash(userOp);
        bytes32 callChainHash = CallVerification.getCallChainHash(config, userOp, solverOps);

        DAppOperation memory dappOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: atlasVerification.getNextNonce(governanceEOA),
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(1),
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return InvalidBundler
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.InvalidBundler, "validCallsResult should be InvalidBundler");
    }

    // GasPriceHigherThanMax cases

    //
    // given an otherwise valid atlas transaction with a userOp.maxFeePerGas lower than tx.gasprice
    // when validCalls is called
    // then it should return GasPriceHigherThanMax
    //
    function test_validCalls_GasPriceHigherThanMax() public {
        // given a valid atlas transaction
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice - 1,
            0,
            block.number + 2,
            ""
        );

        // User signs the userOp
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return GasPriceHigherThanMax
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.GasPriceHigherThanMax, "validCallsResult should be GasPriceHigherThanMax");
    }

    // TxValueLowerThanCallValue cases

    //
    // given an otherwise valid atlas transaction with a msgValue lower than the userOp.value
    // when validCalls is called
    // then it should return TxValueLowerThanCallValue
    //
    function test_validCalls_TxValueLowerThanCallValue() public {
        // given a valid atlas transaction
        UserOperation memory userOp = txBuilder.buildUserOperation(
            userEOA,
            address(dAppControl),
            tx.gasprice + 1,
            1,
            block.number + 2,
            ""
        );

        // User signs the userOp
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return TxValueLowerThanCallValue
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.TxValueLowerThanCallValue, "validCallsResult should be TxValueLowerThanCallValue");
    }

    // Prune invalid solverOps cases

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is the bundler
    // * has an invalid signature
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SolverIsBundlerWithNoSignature_Valid() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = txBuilder.buildSolverOperation(
            userOp,
            "",
            solverOneEOA,
            address(0),
            1e18
        );

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, solverOneEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is not the bundler
    // * has a valid signature
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_SolverIsBundlerWithSignature_Valid() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = buildSolverOperations(userOp);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is not the bundler
    // * has an invalid signature
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverWithNoSignature_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = txBuilder.buildSolverOperation(
            userOp,
            "",
            solverOneEOA,
            address(0),
            1e18
        );

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where tx.gasprice > solverOp.maxFeePerGas
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverWithGasPriceBelowTxprice_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = SolverOperation({
            from: solverOneEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice - 1,
            deadline: userOp.deadline,
            solver: address(0),
            control: userOp.control,
            userOpHash: CallVerification.getUserOperationHash(userOp),
            bidToken: dAppControl.getBidFormat(userOp),
            bidAmount: 1e18,
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where block.number > solverOp.deadline
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverWithDeadlineInPast_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = SolverOperation({
            from: solverOneEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            deadline: block.number - 1,
            solver: address(0),
            control: userOp.control,
            userOpHash: CallVerification.getUserOperationHash(userOp),
            bidToken: dAppControl.getBidFormat(userOp),
            bidAmount: 1e18,
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where solverOp and userOp are from the same address
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverFromUserEOA_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = SolverOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            deadline: block.number - 1,
            solver: address(0),
            control: userOp.control,
            userOpHash: CallVerification.getUserOperationHash(userOp),
            bidToken: dAppControl.getBidFormat(userOp),
            bidAmount: 1e18,
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where solverOp.to != atlas
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverToNotAtlas_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = SolverOperation({
            from: userEOA,
            to: address(0),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            deadline: userOp.deadline,
            solver: address(0),
            control: userOp.control,
            userOpHash: CallVerification.getUserOperationHash(userOp),
            bidToken: dAppControl.getBidFormat(userOp),
            bidAmount: 1e18,
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where solverOp.solver is ATLAS or ATLAS_VERIFICATION
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverContractIsAtlas_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = SolverOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            deadline: userOp.deadline,
            solver: address(atlas),
            control: userOp.control,
            userOpHash: CallVerification.getUserOperationHash(userOp),
            bidToken: dAppControl.getBidFormat(userOp),
            bidAmount: 1e18,
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where solverOp.userOpHash != userOpHash
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_SolverOpUserOpHashWrong_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](1);

        SolverOperation memory solverOp = SolverOperation({
            from: userEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice + 1,
            deadline: userOp.deadline,
            solver: address(0),
            control: userOp.control,
            userOpHash: bytes32(0),
            bidToken: dAppControl.getBidFormat(userOp),
            bidAmount: 1e18,
            data: "",
            signature: new bytes(0)
        });

        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userPK, atlasVerification.getSolverPayload(solverOp));
        solverOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        solverOps[0] = solverOp;
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction with no solverOps
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_NoSolverOps_Simulated_Valid() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    //   and callConfig.zeroSolvers = true
    // when validCalls is called
    // then it should return Valid
    //
    function test_validCalls_NoSolverOps_ZeroSolverSet_Valid() public {
        // given a valid atlas transaction
        callConfig.zeroSolvers = true;
        refreshGlobals();

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_NoSolverOpsSent_NoSolverOp() public {
        // given a valid atlas transaction
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    //   and callConfig.requireFulfillment = true
    // when validCalls is called
    // then it should return NoSolverOp
    //
    function test_validCalls_NoSolverOps_ZeroSolverSet_NoSolverOp() public {
        // given a valid atlas transaction
        callConfig.requireFulfillment = true;
        refreshGlobals();

        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = buildDAppOperation(userOp, solverOps);
        DAppConfig memory config = dAppControl.getDAppConfig(userOp);

        // when validCalls is called
        vm.startPrank(address(atlas));
        ValidCallsResult validCallsResult;
        SolverOperation[] memory prunedSolverOps;
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);

        // then it should return NoSolverOp
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.NoSolverOp, "validCallsResult should be NoSolverOp");
    }

}
