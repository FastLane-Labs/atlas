// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "src/contracts/types/ValidCallsTypes.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { AtlasVerificationBase } from "./AtlasVerification.t.sol";
import { FastLaneErrorsEvents } from "src/contracts/types/Emissions.sol";

contract AtlasVerificationNoncesTest is AtlasVerificationBase {

    function testGetNextNonceReturnsOneForNewAccount_Sequenced() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());
        assertEq(atlasVerification.getNextNonce(userEOA, true), 1, "User seq next nonce should be 1");
        assertEq(atlasVerification.getNextNonce(governanceEOA, true), 1, "Gov seq next nonce should be 1");
    }

    function testGetNextNonceReturnsOneForNewAccount_Async() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).build());
        assertEq(atlasVerification.getNextNonce(userEOA, false), 1, "User async next nonce should be 1");
        assertEq(atlasVerification.getNextNonce(governanceEOA, false), 1, "Gov async next nonce should be 1");
    }

    function testUsingSeqNoncesDoNotChangeNextAsyncNonce() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());
        assertEq(atlasVerification.getNextNonce(userEOA, true), 1, "User next seq nonce should be 1");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 1, "User next async nonce should be 1");

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));
        assertEq(atlasVerification.getNextNonce(userEOA, true), 2, "User next seq nonce should now be 2");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 1, "User next async nonce should still be 1");
    }

    function testUsingAsyncNoncesDoNotChangeNextSeqNonce() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).build());
        assertEq(atlasVerification.getNextNonce(userEOA, true), 1, "User next seq nonce should be 1");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 1, "User next async nonce should be 1");

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));
        assertEq(atlasVerification.getNextNonce(userEOA, true), 1, "User next seq nonce should still be 1");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 2, "User next async nonce should now be 2");
    }

    function testSameNonceCannotBeUsedTwice_UserSequenced_DAppAsync() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).withDappNoncesSequenced(false).build());

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // Fails with UserSignatureInvalid due to re-used user nonce
        userOp = validUserOperation().withNonce(1).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(5).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.UserSignatureInvalid);

        // Fails with DAppSignatureInvalid due to re-used dapp nonce
        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.DAppSignatureInvalid);
    }

    function testSameNonceValidForSeqAndAsyncDApps() public {
        // Set up DApp with sequenced user nonces
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

        // In Sequential DApp: User nonces 1 and 2 are valid
        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Set up DApp with async user nonces
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).build());

        // In Async DApp: User nonces 1 and 2 are valid even though already used in sequential dapp
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
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

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

    function testAsyncNoncesAreValidEvenIfNotSequential() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).build());

        UserOperation memory userOp = validUserOperation().withNonce(1).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Valid if using the async user nonce
        userOp = validUserOperation().withNonce(100).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);

        // Valid if using the async user nonce
        userOp = validUserOperation().withNonce(500).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(3).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);

        // Valid if using the async user nonce
        userOp = validUserOperation().withNonce(2).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(4).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);
    }

    function testFirstEightNonces_DAppSequenced() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withDappNoncesSequenced(true).build());
        
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        // First call initializes at nonce = 1
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // Testing nonces 2 - 8
        for (uint256 i = 2; i < 9; i++) {
            assertEq(atlasVerification.getNextNonce(governanceEOA, true), i, "Next nonce not incrementing as expected");
            
            userOp = validUserOperation().withNonce(i).build();
            solverOps = validSolverOperations(userOp);
            dappOp = validDAppOperation(userOp, solverOps).withNonce(i).signAndBuild(address(atlasVerification), governancePK);
            callAndAssert(ValidCallsCall({
                userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
            ), ValidCallsResult.Valid);
        }

        assertEq(atlasVerification.getNextNonce(governanceEOA, true), 9, "Next nonce should be 9 after 8 seq nonces used");
    }

    function testHighestFullBitmapIncreasesWhenFilled_Async() public {
        // To avoid doing 240 calls, we just modify the relevant storage slot
        // such that the bitmap at index 1 has 239 of 240 nonces used.
        // We test the 240th nonce properly from that point.

        uint128 highestFullBitmap;
        uint256 noncesUsed = 239;
        uint256 bitmap = (2 ** noncesUsed - 1) << 8;
        uint256 highestUsedNonceInBitmap = uint256(noncesUsed);
        uint256 nonceBitmapSlot = highestUsedNonceInBitmap | bitmap;
        bytes32 bitmapKey = keccak256(abi.encode(userEOA, 1));

        // Only concerned with async user nonces in this test
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).withDappNoncesSequenced(true).build());
        
        // Modifying storage slot to have 239 nonces used
        vm.record();
        (uint8 highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmapKey);
        (bytes32[] memory reads, ) = vm.accesses(address(atlasVerification));
        vm.store(address(atlasVerification), reads[0], bytes32(nonceBitmapSlot));
        
        // Check storage slot has been modified correctly
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 0, "Highest full bitmap should 0 if 239 nonces used");
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmapKey);
        assertEq(highestUsedNonce, noncesUsed, "Highest used nonce should be 239");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 240, "Next nonce should be 240 if 239 nonces used");

        // Testing nonce 240
        UserOperation memory userOp = validUserOperation().withNonce(240).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // The next recommended async nonce should be 241 and the highest full bitmap should have increased from 0 to 1
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 1, "Highest full bitmap should be 1 after 240 nonces used");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 241, "Next nonce should be 241 after 240 nonces used");
    }

    function testGetFirstUnusedNonceInBitmap() public {
        MockVerification mockVerification = new MockVerification(address(atlas));

        // empty bitmap should return 1
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(0), 1, "Empty bitmap should return 1");

        // full bitmap should revert
        vm.expectRevert(FastLaneErrorsEvents.NoUnusedNonceInBitmap.selector);
        mockVerification.getFirstUnusedNonceInBitmap(type(uint240).max);

        // bitmap 000...01 should return 2
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(1), 2, "Bitmap 000...01 should return 2");

        // bitmap 000...10 should return 1
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(2), 1, "Bitmap 000...10 should return 1");

        // bitmap 000...11 should return 3
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(3), 3, "Bitmap 000...11 should return 3");

        // bitmap 000...1101_1111_1111_1111_1111_1111_1111_1111_1111 should return 34
        // because 2 full 16-bit chunks used, and 1 bit used in the 3rd chunk before an unused bit
        // 60129542143 = 000...1101_1111_1111_1111_1111_1111_1111_1111_1111
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(60129542143), 34, "Bitmap 000...1101 (+32 more 1s) should return 34");

        // bitmap 0111...111 should return 240 - only last bit unused
        // type(uint240).max - (2 ** 239) = 0111...111 (only last bit unused)
        uint256 leftmostBitFree = type(uint240).max - (2 ** 239);
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(leftmostBitFree), 240, "Bitmap 0111...111 should return 240");
    }
}

contract MockVerification is AtlasVerification {
    constructor(address _atlas) AtlasVerification(_atlas) {}

    function getFirstUnusedNonceInBitmap(uint256 bitmap) public pure returns (uint256) {
        return _getFirstUnusedNonceInBitmap(bitmap);
    }
}
