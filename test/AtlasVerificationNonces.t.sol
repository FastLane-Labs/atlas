// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

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
        uint128 highestFullBitmap;

        // Modify storage such that bitmap at index 1 has 239 of 240 nonces used

        uint256 noncesUsed = 239;
        uint256 bitmap = (2 ** noncesUsed - 1) << 8;
        uint256 highestUsedNonceInBitmap = uint256(noncesUsed);
        uint256 nonceBitmapSlot = highestUsedNonceInBitmap | bitmap;

        console.log("bitmap", bitmap);
        console.log("highestUsedNonceInBitmap", highestUsedNonceInBitmap);
        console.log("nonceBitmapSlot", nonceBitmapSlot);

        // TODO - get the slot and set its value to nonceBitmapSlot

        // Only concerned with async user nonces in this test
        defaultAtlasWithCallConfig(defaultCallConfig().withUserNoncesSequenced(false).withDappNoncesSequenced(true).build());

        // UserOperation memory userOp = validUserOperation().withNonce(239).build();
        // SolverOperation[] memory solverOps = validSolverOperations(userOp);
        // DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        // // First call initializes at nonce = 1
        // doValidCalls(AtlasVerificationBase.ValidCallsCall({
        //     userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        // ));

        bytes32 bitmapKey = keccak256(abi.encode(userEOA, 1));
        
        vm.record();
        (uint8 highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmapKey);

        (bytes32[] memory reads, ) = vm.accesses(address(atlasVerification));
        console.log("Reads[0]", uint256(reads[0]));

        uint256 val = uint256(vm.load(address(atlasVerification), reads[0]));
        console.log("Value at read slot", val);

        vm.store(address(atlasVerification), reads[0], bytes32(nonceBitmapSlot));


        console.log("Next nonce after store", atlasVerification.getNextNonce(userEOA, false));

        (uint8 storedHighestUsedNonce, uint240 storedNonceBitmap) = atlasVerification.nonceBitmaps(bitmapKey);

        console.log("storedHighestUsedNonce", storedHighestUsedNonce);
        console.log("storedNonceBitmap", storedNonceBitmap);

        // Then do a call with nonce 240 to fill the bitmap
        
        

        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 0, "Highest full bitmap should 0 if 239 nonces used");
        (highestUsedNonce,) = atlasVerification.nonceBitmaps(bitmapKey);
        assertEq(highestUsedNonce, noncesUsed, "Highest used nonce should be 239");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 240, "Next nonce should be 240 if 239 nonces used");

        UserOperation memory userOp = validUserOperation().withNonce(240).build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        callAndAssert(ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ), ValidCallsResult.Valid);

        (, highestFullBitmap) = atlasVerification.nonceTrackers(userEOA);
        assertEq(highestFullBitmap, 1, "Highest full bitmap should be 1 after 240 nonces used");
        assertEq(atlasVerification.getNextNonce(userEOA, false), 241, "Next nonce should be 241 after 240 nonces used");
    }
   
}
