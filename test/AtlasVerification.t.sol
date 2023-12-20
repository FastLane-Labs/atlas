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
    // given an otherwise valid atlas transaction where the signer is not enabled by the dApp
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_SignerNotEnabled_Valid() public {
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
        (prunedSolverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, 0, userEOA, true);

        // then it should return Valid
        console.log("validCallsResult: ", uint(validCallsResult));
        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Valid");
    }

    //
    // given an otherwise valid atlas transaction where the control address doesn't match the dApp config.to
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

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

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 0
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 0
    // when validCalls is called with isSimulation = true
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    // TODO: test to do with the nonce bitmap stuff, nfi what its doing

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 1
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 3
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    // UserSignatureInvalid cases

    // userOp signatures are invalid when:
    // * (userOp.signature.length == 0)
    // * _hashTypedDataV4(_getProofHash(userOp)).recover(userOp.signature) != userOp.from

    //
    // given an otherwise valid atlas transaction with an invalid userOp signature
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with an invalid userOp signature
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction where userOp.control != dConfig.to
    // when validCalls is called
    // then it should return UserSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction userOp.nonce greater than uint128.max - 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 0
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 0
    // when validCalls is called with isSimulation = true
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    // TODO: test to do with the nonce bitmap stuff, nfi what its doing

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 1
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 3
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    // TooManySolverOps cases

    //
    // given an otherwise valid atlas transaction with more than (type(uint8).max - 2) = 253 solverOps
    // when validCalls is called
    // then it should return TooManySolverOps
    //

    // UserDeadlineReached cases

    //
    // given an otherwise valid atlas transaction with a userOp.deadline earlier than block.number
    // when validCalls is called
    // then it should return UserDeadlineReached
    //

    // DAppDeadlineReached cases

    //
    // given an otherwise valid atlas transaction with a dAppOp.deadline earlier than block.number
    // when validCalls is called
    // then it should return DAppDeadlineReached
    //

    // InvalidBundler cases

    //
    // given an otherwise valid atlas transaction where the bundler is not the message sender
    // when validCalls is called
    // then it should return InvalidBundler
    //

    // GasPriceHigherThanMax cases

    //
    // given an otherwise valid atlas transaction with a userOp.maxFeePerGas lower than tx.gasprice
    // when validCalls is called
    // then it should return GasPriceHigherThanMax
    //

    // TxValueLowerThanCallValue cases

    //
    // given an otherwise valid atlas transaction with a msgValue lower than the userOp.value
    // when validCalls is called
    // then it should return TxValueLowerThanCallValue
    //

    // Prune invalid solverOps cases

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is the bundler
    // * has an invalid signature
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is not the bundler
    // * has a valid signature
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is not the bundler
    // * has an invalid signature
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where tx.gasprice > solverOp.maxFeePerGas
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where block.number > solverOp.deadline
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where solverOp and userOp are from the same address
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where solverOp.to != atlas
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where solverOp.solver is ATLAS or ATLAS_VERIFICATION
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where solverOp.userOpHash != userOpHash
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    // when validCalls is called with isSimulation = true
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    //   and callConfig.zeroSolvers = true
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    // when validCalls is called
    // then it should return NoSolverOp
    //

    //
    // given an otherwise valid atlas transaction where all solverOps are pruned
    //   and callConfig.requireFulfillment = true
    // when validCalls is called
    // then it should return NoSolverOp
    //

}