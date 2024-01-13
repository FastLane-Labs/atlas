// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "src/contracts/types/ValidCallsTypes.sol";
import { AtlasVerificationBase } from "./AtlasVerification.t.sol";


contract AtlasVerificationNoncesTest is AtlasVerificationBase {

    // Q: Why track lowestEmptyBitmap and highestFullBitmap?
    // A:   - lowestEmptyBitmap = ??
    //      - highestFullBitmap = to calc getNextNonce (highestFullBitmap * 240) + highestUsedNonce
    // --> can we just track highestFullBitmap and highestUsedNonce?


    function testFirstTenNonces_Sequenced() public {
        defaultAtlasWithCallConfig(defaultCallConfig().withSequenced(true).build());
        
        UserOperation memory userOp = validUserOperation().build();
        SolverOperation[] memory solverOps = validSolverOperations(userOp);
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).signAndBuild(address(atlasVerification), governancePK);
        doValidCalls(AtlasVerificationBase.ValidCallsCall({
            userOp: userOp, solverOps: solverOps, dAppOp: dappOp, msgValue: 0, msgSender: userEOA, isSimulation: false}
        ));


        for (uint256 i = 0; i < 10; i++) {
            // TODO make calls, check nonces
        }
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

    // does this need sequenced and non sequenced versions?
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
