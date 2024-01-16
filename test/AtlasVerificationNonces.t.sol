// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "src/contracts/types/ValidCallsTypes.sol";
import { AtlasVerificationBase } from "./AtlasVerification.t.sol";


contract AtlasVerificationNoncesTest is AtlasVerificationBase {
    bool sequenced = true;

    function testFirstEightNonces_Sequenced() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withSequenced(sequenced).build());

        console.log("next gov nonce: ", atlasVerification.getNextNonce(governanceEOA, sequenced), "\n");
        
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        // First call initializes at nonce = 1
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));

        // Testing nonces 2 - 8
        for (uint256 i = 2; i < 9; i++) {

            console.log("next gov nonce: ", atlasVerification.getNextNonce(governanceEOA, sequenced));
            console.log("\nTX ", i, "\n");

            assertEq(atlasVerification.getNextNonce(governanceEOA, sequenced), i, "Next nonce not incrementing as expected");
            

            userOp = validUserOperation().build();
            solverOps = validSolverOperations(userOp);
            dappOp = validDAppOperation(userOp, solverOps).withNonce(i).signAndBuild(address(atlasVerification), governancePK);
            callAndAssert(ValidCallsCall({
                userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
            ), ValidCallsResult.Valid);
        }

        assertEq(atlasVerification.getNextNonce(governanceEOA, sequenced), 9, "Next nonce should be 9 after 8 seq nonces used");
    }

    function test_bitmap2UsedAfterBitmap1Fulled_Sequenced() public {}

    function test_bitmap3UsedAfterBitmap2Fulled_Sequenced() public {
        // Use nonce 1 in bitmap 1
        // Use nonce 239 in bitmap 1 (last in bitmap)
        // Next nonce is 240, which should tick over to bitmap 2
        // Use nonce 279 in bitmap 2 (last in bitmap)
        // Next nonce is 280, which should tick over to bitmap 3
    }

    function test_emptyNoncesInUsedBitmapsCanBeUsed() public {
        // Use nonce 1 in bitmap 1
        // Use nonce 239 in bitmap 1 (last in bitmap)
        // Try using nonce 2 in bitmap 1, should work - unused
        // Next nonce is 240, which should tick over to bitmap 2
        // Try using nonce 3 in bitmap 1, should work - unused
    }

    // does this need sequenced and non sequenced versions? - YES
    function test_usedNoncesCannotBeReused() public {
        // Test nonce 1 works, uses bitmap 1
        // Test using nonce 1 again fails
        // Test nonce 2 works, uses bitmap 1
        // Test using nonce 2 again fails
        // Jump to bitmap 2
        // Test nonce x works, uses bitmap 2
        // Test using nonce x again fails
        // Test using nonce 1 in bitmap 1 still fails
    }
   
}
