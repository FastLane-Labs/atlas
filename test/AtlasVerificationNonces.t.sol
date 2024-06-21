// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "src/contracts/types/ValidCallsTypes.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { AtlasVerificationBase } from "./AtlasVerification.t.sol";

contract AtlasVerificationNoncesTest is AtlasVerificationBase {

    function testGetNextNonceReturnsOneForNewAccount_Sequential() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(true).build());
        assertEq(atlasVerification.getUserNextNonce(userEOA, true), 1, "User seq next nonce should be 1");
        assertEq(atlasVerification.getDAppNextNonce(governanceEOA, true), 1, "Gov seq next nonce should be 1");
    }

    function testGetNextNonceReturnsOneForNewAccount_NonSeq() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(false).build());
        assertEq(atlasVerification.getUserNextNonce(userEOA, false), 1, "User non-seq next nonce should be 1");
        assertEq(atlasVerification.getDAppNextNonce(governanceEOA, false), 1, "Gov non-seq next nonce should be 1");
    }

    function testUsingSeqNoncesDoNotChangeNextNonSeqNonce() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(true).build());
        assertEq(atlasVerification.getUserNextNonce(userEOA, true), 1, "User next seq nonce should be 1");
        assertEq(atlasVerification.getUserNextNonce(userEOA, false), 1, "User next non-seq nonce should be 1");

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));
        assertEq(atlasVerification.getUserNextNonce(userEOA, true), 2, "User next seq nonce should now be 2");
        assertEq(atlasVerification.getUserNextNonce(userEOA, false), 1, "User next non-seq nonce should still be 1");
    }

    function testUsingNonSeqNoncesDoNotChangeNextSeqNonce() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(false).build());
        assertEq(atlasVerification.getUserNextNonce(userEOA, true), 1, "User next seq nonce should be 1");
        assertEq(atlasVerification.getUserNextNonce(userEOA, false), 1, "User next non-seq nonce should be 1");

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));
        assertEq(atlasVerification.getUserNextNonce(userEOA, true), 1, "User next seq nonce should still be 1");
        assertEq(atlasVerification.getUserNextNonce(userEOA, false), 2, "User next non-seq nonce should now be 2");
    }

    function testSameNonceCannotBeUsedTwice_UserSequential_DAppNonSeq() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(true).withDappNoncesSequential(false).build());

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // Fails with UserNonceInvalid due to re-used user nonce
        userOp = validUserOperation().withNonce(1).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(5).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserNonceInvalid);

        // Fails with InvalidDAppNonce due to re-used dapp nonce
        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.InvalidDAppNonce);
    }

    function testSameNonceValidForSeqAndNonSeqDApps() public {
        // Set up DApp with sequential user nonces
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(true).build());

        // In Sequential DApp: User nonces 1 and 2 are valid
        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Set up DApp with non-seq user nonces
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(false).build());

        // In NonSeq DApp: User nonces 1 and 2 are valid even though already used in sequential dapp
        userOp = validUserOperation().withNonce(1).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(3).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(4).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    function testSeqNoncesMustBePerfectlySequential() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(true).build());

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Fails with UserSignatureInvalid due to non-sequential user nonce
        userOp = validUserOperation().withNonce(3).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);

        // Valid if using the sequential user nonce
        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(3).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Fails with UserSignatureInvalid due to non-sequential user nonce
        userOp = validUserOperation().withNonce(999).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(4).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: governanceEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);

        // Valid if using the sequential user nonce
        userOp = validUserOperation().withNonce(3).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(5).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);
    }

    function testNonSeqNoncesAreValidEvenIfNotSequential() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequential(false).build());

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Valid if using the non-seq user nonce
        userOp = validUserOperation().withNonce(100).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);

        // Valid if using the non-seq user nonce
        userOp = validUserOperation().withNonce(500).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(3).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);

        // Valid if using the non-seq user nonce
        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(4).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);
    }

    function testFirstEightNonces_DAppSequential() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withDappNoncesSequential(true).build());
        
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        // First call initializes at nonce = 1
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // Testing nonces 2 - 8
        for (uint256 i = 2; i < 9; i++) {
            assertEq(atlasVerification.getDAppNextNonce(governanceEOA, true), i, "Next nonce not incrementing as expected");
            
            userOp = validUserOperation().withNonce(i).build();
            solverOps = validSolverOperations(userOp);
            dappOp = validDAppOperation(userOp, solverOps).withNonce(i).signAndBuild(address(atlasVerification), governancePK);
            callAndAssert(ValidCallsCall({
                userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
            ), ValidCallsResult.Valid);
        }

        assertEq(atlasVerification.getDAppNextNonce(governanceEOA, true), 9, "Next nonce should be 9 after 8 seq nonces used");
    }

    function testGetNextNonceAfter() public {
        defaultAtlasWithCallConfig(defaultCallConfig().build());
        assertEq(atlasVerification.getUserNextNonceAfter(userEOA, 0), 1, "User next non-seq nonce after 0 should be 1");

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        assertEq(atlasVerification.getUserNextNonceAfter(userEOA, 0), 2, "User next non-seq nonce after 0 should be 2");
        assertEq(atlasVerification.getUserNextNonceAfter(userEOA, 1), 2, "User next non-seq nonce after 1 should be 2");
        assertEq(atlasVerification.getUserNextNonceAfter(userEOA, 2), 3, "User next non-seq nonce after 2 should be 3");
        assertEq(atlasVerification.getUserNextNonceAfter(userEOA, 3), 4, "User next non-seq nonce after 3 should be 4");
    }

    function testMultipleGetNextNonceAfter() public {
        // From a given reference nonce, generate the next 5 operations (to simulate in-flight nonces)
        defaultAtlasWithCallConfig(defaultCallConfig().build());

        UserOperation[] memory userOps = new UserOperation[](5);
        SolverOperation[][] memory solverOps = new SolverOperation[][](5);
        DAppOperation[] memory dappOps = new DAppOperation[](5);

        // Consume nonce 254 for the user, it should not be used again
        userOps[0] = validUserOperation().withNonce(254).build();
        solverOps[0] = validSolverOperations(userOps[0]);
        dappOps[0] = validDAppOperation(userOps[0], solverOps[0]).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOps[0], solverOps: solverOps[0], dAppOp: dappOps[0], msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        uint256 refNonce = 252;
        uint256 userNextNonce = atlasVerification.getUserNextNonceAfter(userEOA, refNonce);

        userOps[0] = validUserOperation().withNonce(userNextNonce).build();
        solverOps[0] = validSolverOperations(userOps[0]);
        dappOps[0] = validDAppOperation(userOps[0], solverOps[0]).withNonce(2).signAndBuild(address(atlasVerification), governancePK);

        userNextNonce = atlasVerification.getUserNextNonceAfter(userEOA, userNextNonce);

        userOps[1] = validUserOperation().withNonce(userNextNonce).build();
        solverOps[1] = validSolverOperations(userOps[1]);
        dappOps[1] = validDAppOperation(userOps[1], solverOps[1]).withNonce(3).signAndBuild(address(atlasVerification), governancePK);

        userNextNonce = atlasVerification.getUserNextNonceAfter(userEOA, userNextNonce);

        userOps[2] = validUserOperation().withNonce(userNextNonce).build();
        solverOps[2] = validSolverOperations(userOps[2]);
        dappOps[2] = validDAppOperation(userOps[2], solverOps[2]).withNonce(4).signAndBuild(address(atlasVerification), governancePK);

        userNextNonce = atlasVerification.getUserNextNonceAfter(userEOA, userNextNonce);

        userOps[3] = validUserOperation().withNonce(userNextNonce).build();
        solverOps[3] = validSolverOperations(userOps[3]);
        dappOps[3] = validDAppOperation(userOps[3], solverOps[3]).withNonce(5).signAndBuild(address(atlasVerification), governancePK);

        userNextNonce = atlasVerification.getUserNextNonceAfter(userEOA, userNextNonce);

        userOps[4] = validUserOperation().withNonce(userNextNonce).build();
        solverOps[4] = validSolverOperations(userOps[4]);
        dappOps[4] = validDAppOperation(userOps[4], solverOps[4]).withNonce(6).signAndBuild(address(atlasVerification), governancePK);

        // Execute all 5 operations in random order
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOps[2], solverOps: solverOps[2], dAppOp: dappOps[2], msgValue: 0, msgSender: userEOA, isSimulation: false}
        )); // Nonce 256
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOps[0], solverOps: solverOps[0], dAppOp: dappOps[0], msgValue: 0, msgSender: userEOA, isSimulation: false}
        )); // Nonce 253
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOps[4], solverOps: solverOps[4], dAppOp: dappOps[4], msgValue: 0, msgSender: userEOA, isSimulation: false}
        )); // Nonce 258
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOps[3], solverOps: solverOps[3], dAppOp: dappOps[3], msgValue: 0, msgSender: userEOA, isSimulation: false}
        )); // Nonce 257
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOps[1], solverOps: solverOps[1], dAppOp: dappOps[1], msgValue: 0, msgSender: userEOA, isSimulation: false}
        )); // Nonce 255

        // Notice nonce 254 was skipped, the highest nonce used was 258 (in userOps[4])
        assertEq(atlasVerification.getUserNextNonceAfter(userEOA, refNonce), 259, "User next non-seq nonce after 252 should be 259");
    }
}
