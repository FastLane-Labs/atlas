// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "src/contracts/types/ValidCallsTypes.sol";
import { AtlasVerificationBase } from "./AtlasVerification.t.sol";


contract AtlasVerificationNoncesTest is AtlasVerificationBase {



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
   
}
