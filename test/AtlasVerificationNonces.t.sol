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
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
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
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
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
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
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
        ), ValidCallsResult.InvalidDAppNonce);
    }

    function testSameNonceValidForSeqAndAsyncDApps() public {
        // Set up DApp with sequenced user nonces
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(true).build());

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
        doValidateCalls(AtlasVerificationBase.ValidCallsCall({
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

        // full bitmap should return 0
        assertEq(mockVerification.getFirstUnusedNonceInBitmap(type(uint240).max), 0, "Full bitmap should return 0");

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

    function testIncrementFullBitmapEdgeCase() public {
        // For edge cases when highestFullAsyncBitmap needs to be re-synced. Example:
        // Bitmap 4 is full
        // Bitmap 3 is full
        // Bitmap 2 only has last nonce unused
        // Bitmap 1 is full
        // ^ in the example above, once last bitmap 2 nonce is used, highestFullAsyncBitmap will be set to 2 but should be 4

        uint128 highestFullBitmap;
        uint8 highestUsedNonce;

        uint256 almostFullBitmapSlot = uint256(239) | (uint256(type(uint240).max - (2 ** 239)) << 8);
        uint256 fullBitmapSlot = uint256(240) | (uint256(type(uint240).max) << 8);

        bytes32 bitmap1Key = keccak256(abi.encode(userEOA, 1));
        bytes32 bitmap2Key = keccak256(abi.encode(userEOA, 2));
        bytes32 bitmap3Key = keccak256(abi.encode(userEOA, 3));
        bytes32 bitmap4Key = keccak256(abi.encode(userEOA, 4));

        // Only concerned with async user nonces in this test
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).withDappNoncesSequenced(true).build());
        
        // Modify bitmaps 3 and 4 to be full
        vm.record();
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap3Key);
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap4Key);
        (bytes32[] memory reads, ) = vm.accesses(address(atlasVerification));
        vm.store(address(atlasVerification), reads[0], bytes32(fullBitmapSlot));
        vm.store(address(atlasVerification), reads[1], bytes32(fullBitmapSlot));

        // Modify bitmaps 1 and 2 to be almost full
        vm.record();
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap1Key);
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap2Key);
        (reads, ) = vm.accesses(address(atlasVerification));
        vm.store(address(atlasVerification), reads[0], bytes32(almostFullBitmapSlot));
        vm.store(address(atlasVerification), reads[1], bytes32(almostFullBitmapSlot));

        // Check highestFullAsyncBitmap is still 0
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 0, "Highest full bitmap should 0 if 239 nonces used");

        // Now use nonce 240, which should set highestFullAsyncBitmap to 1
        UserOperation memory userOp = validUserOperation().withNonce(240).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).withNonce(1).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        // Check highestFullAsyncBitmap is now 1
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 1, "Highest full bitmap value should be 1");

        // getNextNonce should return 480 = (240 used in slot 1 + 239 used in slot 2)
        assertEq(atlasVerification.getNextNonce(userEOA, false), 480, "Next unused nonce should be 480");

        // Now use nonce 480, which should full bitmap 2 and set highest bitmap to the next consecutive full bitmap (4)
        userOp = validUserOperation().withNonce(480).build();
        solverOps = validSolverOperations(userOp);
        dappOp = validDAppOperation(userOp, solverOps).withNonce(2).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, isSimulation: false, msgValue: 0, msgSender: userEOA}
        ), ValidCallsResult.Valid);

        // Check highestFullAsyncBitmap is now 4
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 4, "Highest full bitmap value should be 4");

        // getNextNonce should return the correct next nonce = 240 * 4 + 1 = 961
        assertEq(atlasVerification.getNextNonce(userEOA, false), 961, "Next unused nonce should be 961");

        // MAIN PART OF TEST: Call manuallyUpdateNonceTracker to set highestFullAsyncBitmap to 4
        vm.prank(userEOA);
        atlasVerification.manuallyUpdateNonceTracker(userEOA);

        // Check highestFullAsyncBitmap is now 4 and getNextNonce returns 240 * 4 + 1 = 961
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 4, "Highest full bitmap should be 4 after manually updating");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 961, "Next unused nonce should be 961");
    }

    function testManuallyUpdateNonceTracker() public {
        uint128 highestFullBitmap;
        uint8 highestUsedNonce;

        uint256 fullBitmapSlot = uint256(240) | (uint256(type(uint240).max) << 8);
        bytes32 bitmap1Key = keccak256(abi.encode(userEOA, 1));
        bytes32 bitmap2Key = keccak256(abi.encode(userEOA, 2));
        bytes32 bitmap3Key = keccak256(abi.encode(userEOA, 3));
        bytes32 bitmap4Key = keccak256(abi.encode(userEOA, 4));

        // Only concerned with async user nonces in this test
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).withDappNoncesSequenced(true).build());
        
        // Modify bitmaps 1 - 4 to be full
        vm.record();
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap1Key);
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap2Key);
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap3Key);
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmap4Key);
        (bytes32[] memory reads, ) = vm.accesses(address(atlasVerification));
        vm.store(address(atlasVerification), reads[0], bytes32(fullBitmapSlot));
        vm.store(address(atlasVerification), reads[1], bytes32(fullBitmapSlot));
        vm.store(address(atlasVerification), reads[2], bytes32(fullBitmapSlot));
        vm.store(address(atlasVerification), reads[3], bytes32(fullBitmapSlot));

        // Check highestFullAsyncBitmap is still 0
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 0, "Highest full bitmap should 0 because not updated yet");

        // MAIN PART OF TEST: Call manuallyUpdateNonceTracker to update highestFullAsyncBitmap to 4
        vm.prank(userEOA);
        atlasVerification.manuallyUpdateNonceTracker(userEOA);

        // Check highestFullAsyncBitmap is now 4
        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 4, "Highest full bitmap should be 4 after manually updating");

        // getNextNonce should return 240 * 4 + 1 = 961
        assertEq(atlasVerification.getNextNonce(userEOA, false), 961, "Next unused nonce should be 961");
    }
}

contract MockVerification is AtlasVerification {
    constructor(address _atlas) AtlasVerification(_atlas) {}

    function getFirstUnusedNonceInBitmap(uint256 bitmap) public pure returns (uint256) {
        return _getFirstUnusedNonceInBitmap(bitmap);
    }
}
