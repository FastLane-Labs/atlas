// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "src/contracts/types/ValidCallsTypes.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";
import { AtlasBaseTest } from "./base/AtlasBaseTest.t.sol";
import { CallVerification } from "src/contracts/libraries/CallVerification.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import { DummyDAppControlBuilder } from "./helpers/DummyDAppControlBuilder.sol";
import { CallConfigBuilder } from "./helpers/CallConfigBuilder.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";

// 
// ---- TEST HELPERS BEGIN HERE ---- //
// --- (Also used in other files) --- //
// - Scroll down for the actual tests - //
//

contract AtlasVerificationBase is AtlasBaseTest {
    DummyDAppControl dAppControl;

    struct ValidCallsCall {
        UserOperation userOp;
        SolverOperation[] solverOps;
        DAppOperation dAppOp;
        uint256 msgValue;
        address msgSender;
        bool isSimulation;
    }

    function defaultCallConfig() public returns (CallConfigBuilder) {
        return new CallConfigBuilder();
    }

    function defaultDAppControl() public returns (DummyDAppControlBuilder) {
        return new DummyDAppControlBuilder()
            .withEscrow(address(atlas))
            .withGovernance(governanceEOA)
            .withCallConfig(defaultCallConfig().build());
    }

    function validUserOperation() public returns (UserOperationBuilder) {
        return new UserOperationBuilder()
            .withFrom(userEOA)
            .withTo(address(dAppControl))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(tx.gasprice + 1)
            .withNonce(address(atlasVerification), userEOA)
            .withDeadline(block.number + 2)
            .withControl(address(dAppControl))
            .withSessionKey(address(0))
            .withData("")
            .sign(address(atlasVerification), userPK);
    }

    function validSolverOperation(UserOperation memory userOp) public returns (SolverOperationBuilder) {
        return new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withData("")
            .withUserOpHash(userOp)
            .sign(address(atlasVerification), solverOnePK);
    }

    function validSolverOperations(UserOperation memory userOp) public returns (SolverOperation[] memory) {
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp).build();
        return solverOps;
    }

    function validDAppOperation(DAppConfig memory config, UserOperation memory userOp, SolverOperation[] memory solverOps) public returns (DAppOperationBuilder) {
        bytes32 callChainHash = CallVerification.getCallChainHash(config, userOp, solverOps);
        return new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(2_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withBundler(address(0))
            .withUserOpHash(userOp)
            .withCallChainHash(callChainHash)
            .sign(address(atlasVerification), governancePK);
    }

    function validDAppOperation(UserOperation memory userOp, SolverOperation[] memory solverOps) public returns (DAppOperationBuilder) {
        return new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(2_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withBundler(address(0))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK);
    }

    function doValidateCalls(ValidCallsCall memory call) public returns (ValidCallsResult result) {
        DAppConfig memory config = dAppControl.getDAppConfig(call.userOp);
        vm.startPrank(address(atlas));
        (, result) = atlasVerification.validateCalls(
            config,
            call.userOp,
            call.solverOps,
            call.dAppOp,
            call.msgValue,
            call.msgSender,
            call.isSimulation);
        vm.stopPrank();
    }

    function assertValidCallsResult(ValidCallsResult actual, ValidCallsResult expected) public {
        console.log("validCallsResult actual: ", uint(actual));
        console.log("validCallsResult expected: ", uint(expected));
        assertTrue(actual == expected, "validCallsResult different to expected");
    }

    function callAndAssert(ValidCallsCall memory call, ValidCallsResult expected) public {
        ValidCallsResult result;
        result = doValidateCalls(call);
        assertValidCallsResult(result, expected);
    }

    function callAndExpectRevert(ValidCallsCall memory call, bytes4 selector) public {
        vm.expectRevert(selector);
        doValidateCalls(call);
    }

    function defaultAtlasEnvironment() public {
        AtlasBaseTest.setUp();
        dAppControl = defaultDAppControl().buildAndIntegrate(atlasVerification);
    }

    function defaultAtlasWithCallConfig(CallConfig memory callConfig) public {
        AtlasBaseTest.setUp();
        dAppControl = defaultDAppControl().withCallConfig(callConfig).buildAndIntegrate(atlasVerification);
    }
}

//
// ---- TESTS BEGIN HERE ---- //
//

contract AtlasVerificationTest is AtlasVerificationBase {

    // Valid cases

    // 
    // given a default atlas environment
    //   and valid user, solver and dapp operations
    // when validCalls is called from the userEOA
    // then it should return Valid
    //
    function test_validCalls_ValidResult() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    // InvalidCaller cases

    //
    // given a default atlas environment
    //   and valid user, solver and dapp operations 
    // when validCalls is called from the userEOA
    //  and the caller is not the atlas contract
    // then it should revert with InvalidCaller
    //
    function test_validCalls_InvalidCallerResult() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        DAppConfig memory config = dAppControl.getDAppConfig(userOp);
        vm.expectRevert(AtlasVerification.InvalidCaller.selector);
        atlasVerification.validateCalls(config, userOp, solverOps, dappOp, 0, userEOA, false);
    }

    //
    // InvalidAuctioneer cases
    //
    
    // 
    // given a default atlas environment
    //   and a callConfig with verifyCallChainHash = true
    //   and valid user, solver and dapp operations 
    // when validCalls is called from the userEOA
    // then it should return Valid
    //
    function test_validCalls_VerifyCallChainHash_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withVerifyCallChainHash(true).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and a callConfig with verifyCallChainHash = true
    //   and otherwise valid user, solver and dapp operations
    //      where the dapp operation has an empty callChainHash
    // when validCalls is called from the userEOA
    // then it should return InvalidAuctioneer
    //
    function test_validCalls_VerifyCallChainHash_InvalidAuctioneer() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withVerifyCallChainHash(true).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps)
            .withCallChainHash(bytes32(0))
            .signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidAuctioneer);
    }

    //
    // given a default atlas environment
    //   and a callConfig with verifyCallChainHash = true
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation has an empty callChainHash
    // when validCalls is called from the userEOA
    //   and isSimulation = true
    // then it should return Valid
    //
    function test_validCalls_Simulated_VerifyCallChainHash_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withVerifyCallChainHash(true).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps)
            .withCallChainHash(bytes32(0))
            .signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: true}
        ), ValidCallsResult.Valid);
    }

    // DAppSignatureInvalid cases

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation has an empty signature
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_BrokenSignature_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withSignature(bytes("")).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.DAppSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation is signed by the wrong PK
    // when validCalls is called from the userEOA
    //   and isSimulation = true
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_Simulated_BrokenSignature_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), userPK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: true}
        ), ValidCallsResult.DAppSignatureInvalid);
    }

    // 
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //   and the governanceEOA is not a valid signatory
    //   and callConfig.userAuctioneer = true
    // when validCalls is called from the userEOA
    // then it should bypass signatory verification
    //   and return Valid
    //
    function test_validCalls_SignerNotEnabled_BypassSignatory_UserAuctioneer_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserAuctioneer(true).build());
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = validUserOperation().withSessionKey(governanceEOA).signAndBuild(address(atlasVerification), governancePK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    // 
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //   and the governanceEOA is not a valid signatory
    //   and callConfig.solverAuctioneer = true
    // when validCalls is called from the solverOneEOA
    // then it should bypass signatory verification
    //   and return Valid
    //
    function test_validCalls_SignerNotEnabled_BypassSignatory_SolverAuctioneer_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withSolverAuctioneer(true).build());
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withFrom(solverOneEOA).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: solverOneEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //   and the governanceEOA is not a valid signatory
    //   and callConfig.unknownAuctioneer = true
    // when validCalls is called from the userEOA
    // then it should bypass signatory verification
    //   and return Valid
    //
    function test_validCalls_SignerNotEnabled_BypassSignatory_UnknownAuctioneer_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUnknownAuctioneer(true).build());
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //   and the governanceEOA is not a valid signatory
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_SignerNotEnabled_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();
        vm.prank(governanceEOA);
        atlasVerification.removeSignatory(address(dAppControl), governanceEOA);

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.DAppSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation control address is different to the dapp config to address
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    //
    function test_validCalls_ControlConfigMismatch_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withControl(address(0)).signAndBuild(address(atlasVerification), governancePK);
        
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.DAppSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is uint128.max
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    // because anything above uint128.max - 1 is not a valid nonce
    //
    function test_validCalls_NonceTooLarge_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(type(uint128).max).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidDAppNonce);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is zero
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    // because zero is not a valid nonce
    //
    function test_validCalls_NonceIsZero_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(0).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidDAppNonce);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is zero
    // when validCalls is called from the userEOA
    //   and isSimulation = true
    // then it should return Valid
    // because zero is a valid nonce for simulations
    //
    function test_validCalls_NonceIsZero_Simulated_DAppSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(0).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: true}
        ), ValidCallsResult.InvalidDAppNonce);
    }

    //
    // given a default atlas environment
    //   and callConfig.sequenced = false
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is one
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because one has not been used before
    //
    function test_validCalls_UnsequencedNonceIsOne_Valid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    // TODO: tests to do with the nonce bitmap stuff, no idea what is going on in there yet

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is one
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because one is the first valid nonce for sequenced calls
    //  and this is the first call for the user
    //
    function test_validCalls_SequencedNonceIsOne_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withDappNoncesSequenced(true).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is two
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    // because one is the first valid nonce for sequenced calls
    //  and this is the first call for the user
    //
    function test_validCalls_SequencedNonceIsTwo_DAppSignatureInvalid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withDappNoncesSequenced(true).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidDAppNonce);
    }

    //
    // given an otherwise valid atlas transaction with a dAppOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the last dAppOp.nonce for the user is 1
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is two
    //   and the last dapp operation nonce for the user is one
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because one is the first valid nonce for sequenced calls
    //  and this is the first call for the user
    //
    function test_validCalls_SequencedNonceWasOneIsNowTwo_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

        // these first ops are to increment the nonce to 1
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // this is the actual testcase
        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    // 
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp operation nonce is three
    //   and the last dapp operation nonce for the user is one
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    // because the current nonce for the user is 1
    //  and the next valid nonce is 2
    //
    function test_validCalls_SequencedNonceWasOneIsNowThree_DAppSignatureInvalid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withDappNoncesSequenced(true).build());

        // these first ops are to increment the nonce to 1
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();
        doValidateCalls(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // this is the actual testcase
        userOp = validUserOperation().build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(3).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidDAppNonce);
    }

    // UserSignatureInvalid cases

    // userOp signatures are invalid when:
    // * (userOp.signature.length == 0)
    // * _hashTypedDataV4(_getProofHash(userOp)).recover(userOp.signature) != userOp.from

    //
    // gived a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the userOp signature is blank
    // when validCalls is called from the governanceEOA
    // then it should return UserSignatureInvalid
    // because the signature is not valid for the user
    //
    function test_validCalls_InvalidUserSignatureBlank_BundlerNotUser_UserSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withSignature(bytes("")).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the userOp signature is signed by someone else
    // when validCalls is called from the governanceEOA
    // then it should return UserSignatureInvalid
    // because the signature is not valid for the user
    //
    function test_validCalls_InvalidUserSignatureWrongEOA_BundlerNotUser_UserSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().signAndBuild(address(atlasVerification), governancePK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the userOp signature is blank
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because the user op signature is not required when the bundler is the user
    //
    function test_validCalls_InvalidUserSignatureBlank_BundlerIsUser_UserSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withSignature(bytes("")).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the userOp signature is blank
    // when validCalls is called from the governanceEOA
    //   and isSimulation = true
    // then it should return Valid
    // because the user op signature is not required for simulations
    //
    function test_validCalls_InvalidUserSignatureBlank_Simulated_Valid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withSignature(bytes("")).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: true}
        ), ValidCallsResult.Valid);
    }


    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the user op control address is different to the dapp config to address
    // when validCalls is called from the userEOA
    // then it should return UserSignatureInvalid
    // because the user op signature control address must match the dapp config to address
    //
    function test_validCalls_InvalidUserOpControl_UserSignatureInvalid() public {
        defaultAtlasEnvironment();
        DAppConfig memory config = DAppConfig({ to: address(dAppControl), callConfig: CallBits.encodeCallConfig(defaultCallConfig().build()), bidToken: address(0) });

        UserOperation memory userOp = validUserOperation().withControl(address(0)).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(config, userOp, solverOps).withControl(address(dAppControl)).signAndBuild(address(atlasVerification), governancePK);

        ValidCallsResult result;
        vm.startPrank(address(atlas));
        (, result) = atlasVerification.validateCalls(
            config,
            userOp,
            solverOps,
            dappOp,
            0,
            userEOA,
            false);
        vm.stopPrank();
        assertValidCallsResult(result, ValidCallsResult.UserSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is greater than uint128.max - 1
    // when validCalls is called from the userEOA
    // then it should return UserSignatureInvalid
    // because anything above uint128.max - 1 is not a valid nonce
    //
    function test_validCalls_UserOpNonceToBig_UserSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withNonce(type(uint128).max).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);
    }
    
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is zero
    // when validCalls is called from the userEOA
    // then it should return UserSignatureInvalid
    // because zero is not a valid nonce
    //
    function test_validCalls_UserOpNonceIsZero_UserSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withNonce(0).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is zero
    // when validCalls is called from the userEOA
    //   and isSimulation = true
    // then it should return UserSignatureInvalid
    // because zero is never a valid nonce
    //
    function test_validCalls_UserOpNonceIsZero_Simulated_UserSignatureInvalid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withNonce(0).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: true}
        ), ValidCallsResult.UserSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is one
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because one has not been used before
    //
    function test_validCalls_UserOpNonceIsOne_Valid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withNonce(1).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    // TODO: test to do with the nonce bitmap stuff, nfi what its doing

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is one
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because one is the first valid nonce for sequenced calls
    //  and this is the first call for the user
    //
    function test_validCalls_SequencedUserOpNonceIsOne_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

        UserOperation memory userOp = validUserOperation().withNonce(1).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 2
    //   and the callConfig.sequenced = true
    //   and the nonce is uninitialized for the user
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is two
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    // because one is the first valid nonce for sequenced calls
    //  and this is the first call for the user
    //
    function test_validCalls_SequencedUserOpNonceIsTwo_UserSignatureInvalid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

        UserOperation memory userOp = validUserOperation().withNonce(2).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);
    }

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is two
    //  and the last user operation nonce for the user is one
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because the current nonce for the user is 1
    //  and the next valid nonce is 2
    //
    function test_validCalls_SequencedUserOpNonceIsTwo_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

        // increment the nonce to 1
        UserOperation memory userOp = validUserOperation().signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();
        doValidateCalls(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: false}
        ));

        // this is the actual testcase
        userOp = validUserOperation().withNonce(2).signAndBuild(address(atlasVerification), userPK);
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given an otherwise valid atlas transaction with a userOp.nonce of 3
    //   and the callConfig.sequenced = true
    //   and the last nonce for the user is 1
    // when validCalls is called
    // then it should return DAppSignatureInvalid
    //

    //
    // given a default atlas environment
    //   and callConfig.sequenced = true
    //   and otherwise valid user, solver and dapp operations
    //     where the user operation nonce is three
    //   and the last user operation nonce for the user is one
    // when validCalls is called from the userEOA
    // then it should return DAppSignatureInvalid
    // because the current nonce for the user is 1
    //   and the next valid nonce is 2
    //
    function test_validCalls_SequencedUserOpNonceIsThree_UserSignatureInvalid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

        // increment the nonce to 1
        UserOperation memory userOp = validUserOperation().signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();
        doValidateCalls(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: false}
        ));

        // this is the actual testcase
        userOp = validUserOperation().withNonce(3).signAndBuild(address(atlasVerification), userPK);
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);
    }

    // TooManySolverOps cases

    //
    // given an otherwise valid atlas transaction with more than (type(uint8).max - 2) = 253 solverOps
    // when validCalls is called
    // then it should return TooManySolverOps
    //

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where there are more than 253 solverOps
    // when validCalls is called from the userEOA
    // then it should return TooManySolverOps
    // because 253 is the maximum number of solverOps
    //
    function test_validCalls_TooManySolverOps() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](255);
        SolverOperation memory solverOp = validSolverOperation(userOp).build();
        for (uint i = 0; i < 255; i++) {
            solverOps[i] = solverOp;
        }
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.TooManySolverOps);
    }

    // UserDeadlineReached cases

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the userOp.deadline is earlier than block.number
    // when validCalls is called from the userEOA
    // then it should return UserDeadlineReached
    // because the deadline has passed
    //
    function test_validCalls_UserDeadlineReached() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withDeadline(block.number - 1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserDeadlineReached);
    }

    // DAppDeadlineReached cases

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dappOp.deadline is earlier than block.number
    // when validCalls is called from the userEOA
    // then it should return DAppDeadlineReached
    // because the deadline has passed
    //
    function test_validCalls_DAppDeadlineReached() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withDeadline(block.number - 1).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.DAppDeadlineReached);
    }

    // InvalidBundler cases

    //
    // given an otherwise valid atlas transaction where the bundler is not the message sender
    // when validCalls is called
    // then it should return InvalidBundler
    //

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the dapp op bundler is not the message sender
    // when validCalls is called from the userEOA
    // then it should return InvalidBundler
    // because the bundler must be the message sender
    //
    function test_validCalls_InvalidBundler() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withBundler(address(1)).signAndBuild(address(atlasVerification), governancePK);

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidBundler);
    }

    // GasPriceHigherThanMax cases

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the userOp.maxFeePerGas is lower than tx.gasprice
    // when validCalls is called from the userEOA
    // then it should return GasPriceHigherThanMax
    // because the userOp.maxFeePerGas must be higher than tx.gasprice
    //
    function test_validCalls_GasPriceHigherThanMax() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withMaxFeePerGas(tx.gasprice - 1).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.GasPriceHigherThanMax);
    }

    // TxValueLowerThanCallValue cases

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the msgValue is lower than the userOp.value
    // when validCalls is called from the userEOA
    // then it should return TxValueLowerThanCallValue
    // because the msgValue must be higher than the userOp.value
    //
    function test_validCalls_TxValueLowerThanCallValue() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().withValue(1).signAndBuild(address(atlasVerification), userPK);
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.TxValueLowerThanCallValue);
    }

    // Prune invalid solverOps cases

    //
    // given an otherwise valid atlas transaction with a solverOp that:
    // * is the bundler
    // * has an invalid signature
    // when validCalls is called
    // then it should return Valid
    //

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op has an invalid signature
    // when validCalls is called from the solverOneEOA
    // then it should return Valid
    // because the solver op signature is not required when the solver is the bundler
    //
    function test_validCalls_SolverIsBundlerWithNoSignature_Valid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        SolverOperation memory solverOp = validSolverOperation(userOp).withSignature(bytes("")).build();
        solverOps[0] = solverOp;
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: solverOneEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op has an invalid signature
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the solver op signature is required when the solver is not the bundler
    //
    // function test_validCalls_SolverWithNoSignature_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withSignature(bytes("")).build();
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    //
    // given an otherwise valid atlas transaction where tx.gasprice > solverOp.maxFeePerGas
    // when validCalls is called
    // then it should return NoSolverOp
    //

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op maxFeePerGas is lower than tx.gasprice
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the solver op maxFeePerGas must be higher than tx.gasprice
    //
    // function test_validCalls_SolverWithGasPriceBelowTxprice_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withMaxFeePerGas(tx.gasprice - 1).signAndBuild(address(atlasVerification), solverOnePK);
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op deadline is earlier than block.number
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the solver op deadline must be block.number or later
    //
    // function test_validCalls_SolverWithDeadlineInPast_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withDeadline(block.number - 1).signAndBuild(address(atlasVerification), solverOnePK);
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op and user op are from the same address
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the user can't also be the solver
    //
    // function test_validCalls_SolverFromUserEOA_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withFrom(userEOA).signAndBuild(address(atlasVerification), userPK);
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op is not calling the atlas contract
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the solver op must call the atlas contract
    //
    // function test_validCalls_SolverToNotAtlas_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withTo(address(0)).signAndBuild(address(atlasVerification), solverOnePK);
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op contract is the atlas contract
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the solver op contract must not be atlas
    //
    // function test_validCalls_SolverContractIsAtlas_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withSolver(address(atlas)).signAndBuild(address(atlasVerification), solverOnePK);
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    // TODO Redo test with new solverOp sequential validation system
    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where the solver op userOpHash is not the same as the user op userOpHash
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because the solver op userOpHash must be the same as the user op userOpHash
    //
    // function test_validCalls_SolverOpUserOpHashWrong_NoSolverOp() public {
    //     defaultAtlasEnvironment();

    //     UserOperation memory userOp = validUserOperation().build();
    //     SolverOperation[] memory solverOps = new SolverOperation[](1);
    //     SolverOperation memory solverOp = validSolverOperation(userOp).withUserOpHash(bytes32(0)).signAndBuild(address(atlasVerification), solverOnePK);
    //     solverOps[0] = solverOp;
    //     DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

    //     callAndAssert(ValidCallsCall({
    //         userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
    //     ), ValidCallsResult.NoSolverOp);
    // }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where there are no solver ops
    // when validCalls is called from the userEOA
    //   and isSimulation = true
    // then it should return Valid
    // because no solver ops is valid for simulations
    //
    function test_validCalls_NoSolverOps_Simulated_Valid() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: true}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where there are no solver ops
    //   and callConfig.zeroSolvers = true
    // when validCalls is called from the userEOA
    // then it should return Valid
    // because no solver ops is valid when zeroSolvers is true
    //
    function test_validCalls_NoSolverOps_ZeroSolverSet_Valid() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withZeroSolvers(true).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where there are no solver ops
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because no solver ops is not valid by default
    //
    function test_validCalls_NoSolverOpsSent_NoSolverOp() public {
        defaultAtlasEnvironment();

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.NoSolverOp);
    }

    //
    // given a default atlas environment
    //   and otherwise valid user, solver and dapp operations
    //     where all solver ops are pruned
    //   and callConfig.requireFulfillment = true
    //   and callConfig.zeroSolvers = true
    // when validCalls is called from the userEOA
    // then it should return NoSolverOp
    // because all solver ops are pruned
    //
    function test_validCalls_NoSolverOps_ZeroSolverSet_NoSolverOp() public {
        // Should return NoSolverOp in the `if (!dConfig.callConfig.allowsZeroSolvers())` branch
        defaultAtlasWithCallConfig(defaultCallConfig().withRequireFulfillment(true).withZeroSolvers(false).build());

        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.NoSolverOp);

        // Should return NoSolverOp in the `if (dConfig.callConfig.needsFulfillment())` branch
        defaultAtlasWithCallConfig(defaultCallConfig().withRequireFulfillment(true).withZeroSolvers(true).build());

        userOp = validUserOperation().build();
        solverOps = new SolverOperation[](0);
        dappOp = validDAppOperation(userOp, solverOps).build();

        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.NoSolverOp);
    }

    function testGetDomainSeparatorInAtlasVerification() public {
        bytes32 hashedName = keccak256(bytes("AtlasVerification"));
        bytes32 hashedVersion = keccak256(bytes("0.0.1"));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 predictedDomainSeparator = keccak256(abi.encode(typeHash, hashedName, hashedVersion, block.chainid, address(atlasVerification)));
        bytes32 domainSeparator = atlasVerification.getDomainSeparator();

        assertEq(predictedDomainSeparator, domainSeparator);
    }
}
