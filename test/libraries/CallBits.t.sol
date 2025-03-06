// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { CallBits } from "../../src/contracts/libraries/CallBits.sol";
import "../../src/contracts/types/UserOperation.sol";
import "../base/TestUtils.sol";

contract CallBitsTest is Test {
    using CallBits for uint32;

    CallConfig callConfig1;
    CallConfig callConfig2;

    function setUp() public {
        callConfig1 = CallConfig({
            userNoncesSequential: false,
            dappNoncesSequential: true,
            requirePreOps: false,
            trackPreOpsReturnData: true,
            trackUserReturnData: false,
            delegateUser: true,
            requirePreSolver: false,
            requirePostSolver: true,
            zeroSolvers: false,
            reuseUserOp: true,
            userAuctioneer: false,
            solverAuctioneer: true,
            unknownAuctioneer: false,
            verifyCallChainHash: true,
            forwardReturnData: false,
            requireFulfillment: true,
            trustedOpHash: false,
            invertBidValue: true,
            exPostBids: false,
            allowAllocateValueFailure: true
        });

        callConfig2 = CallConfig({
            userNoncesSequential: !callConfig1.userNoncesSequential,
            dappNoncesSequential: !callConfig1.dappNoncesSequential,
            requirePreOps: !callConfig1.requirePreOps,
            trackPreOpsReturnData: !callConfig1.trackPreOpsReturnData,
            trackUserReturnData: !callConfig1.trackUserReturnData,
            delegateUser: !callConfig1.delegateUser,
            requirePreSolver: !callConfig1.requirePreSolver,
            requirePostSolver: !callConfig1.requirePostSolver,
            zeroSolvers: !callConfig1.zeroSolvers,
            reuseUserOp: !callConfig1.reuseUserOp,
            userAuctioneer: !callConfig1.userAuctioneer,
            solverAuctioneer: !callConfig1.solverAuctioneer,
            unknownAuctioneer: !callConfig1.unknownAuctioneer,
            verifyCallChainHash: !callConfig1.verifyCallChainHash,
            forwardReturnData: !callConfig1.forwardReturnData,
            requireFulfillment: !callConfig1.requireFulfillment,
            trustedOpHash: !callConfig1.trustedOpHash,
            invertBidValue: !callConfig1.invertBidValue,
            exPostBids: !callConfig1.exPostBids,
            allowAllocateValueFailure: !callConfig1.allowAllocateValueFailure
        });
    }

    function testEncodeCallConfig() public view {
        string memory expectedBitMapString = "00000000000010101010101010101010";
        assertEq(
            TestUtils.uint32ToBinaryString(CallBits.encodeCallConfig(callConfig1)),
            expectedBitMapString,
            "callConfig1 incorrect"
        );

        expectedBitMapString = "00000000000001010101010101010101";
        assertEq(
            TestUtils.uint32ToBinaryString(CallBits.encodeCallConfig(callConfig2)),
            expectedBitMapString,
            "callConfig2 incorrect"
        );
    }
    
    function testDecodeCallConfig() public view {
        uint32 encodedCallConfig = CallBits.encodeCallConfig(callConfig1);
        CallConfig memory decodedCallConfig = encodedCallConfig.decodeCallConfig();
        assertEq(decodedCallConfig.userNoncesSequential, false, "userNoncesSequential 1 incorrect");
        assertEq(decodedCallConfig.dappNoncesSequential, true, "dappNoncesSequential 1 incorrect");
        assertEq(decodedCallConfig.requirePreOps, false, "requirePreOps 1 incorrect");
        assertEq(decodedCallConfig.trackPreOpsReturnData, true, "trackPreOpsReturnData 1 incorrect");
        assertEq(decodedCallConfig.trackUserReturnData, false, "trackUserReturnData 1 incorrect");
        assertEq(decodedCallConfig.delegateUser, true, "delegateUser 1 incorrect");
        assertEq(decodedCallConfig.requirePreSolver, false, "requirePreSolver 1 incorrect");
        assertEq(decodedCallConfig.requirePostSolver, true, "requirePostSolver 1 incorrect");
        assertEq(decodedCallConfig.zeroSolvers, false, "zeroSolvers 1 incorrect");
        assertEq(decodedCallConfig.reuseUserOp, true, "reuseUserOp 1 incorrect");
        assertEq(decodedCallConfig.userAuctioneer, false, "userAuctioneer 1 incorrect");
        assertEq(decodedCallConfig.solverAuctioneer, true, "solverAuctioneer 1 incorrect");
        assertEq(decodedCallConfig.unknownAuctioneer, false, "unknownAuctioneer 1 incorrect");
        assertEq(decodedCallConfig.verifyCallChainHash, true, "verifyCallChainHash 1 incorrect");
        assertEq(decodedCallConfig.forwardReturnData, false, "forwardPreOpsReturnData 1 incorrect");
        assertEq(decodedCallConfig.requireFulfillment, true, "requireFulfillment 1 incorrect");
        assertEq(decodedCallConfig.trustedOpHash, false, "trustedOpHash 1 incorrect");
        assertEq(decodedCallConfig.invertBidValue, true, "invertBidValue 1 incorrect");
        assertEq(decodedCallConfig.exPostBids, false, "exPostBids 1 incorrect");
        assertEq(decodedCallConfig.allowAllocateValueFailure, true, "allowAllocateValueFailure 1 incorrect");

        encodedCallConfig = CallBits.encodeCallConfig(callConfig2);
        decodedCallConfig = encodedCallConfig.decodeCallConfig();
        assertEq(decodedCallConfig.userNoncesSequential, true, "userNoncesSequential 2 incorrect");
        assertEq(decodedCallConfig.dappNoncesSequential, false, "dappNoncesSequential 2 incorrect");
        assertEq(decodedCallConfig.requirePreOps, true, "requirePreOps 2 incorrect");
        assertEq(decodedCallConfig.trackPreOpsReturnData, false, "trackPreOpsReturnData 2 incorrect");
        assertEq(decodedCallConfig.trackUserReturnData, true, "trackUserReturnData 2 incorrect");
        assertEq(decodedCallConfig.delegateUser, false, "delegateUser 2 incorrect");
        assertEq(decodedCallConfig.requirePreSolver, true, "requirePreSolver 2 incorrect");
        assertEq(decodedCallConfig.requirePostSolver, false, "requirePostSolver 2 incorrect");
        assertEq(decodedCallConfig.zeroSolvers, true, "zeroSolvers 2 incorrect");
        assertEq(decodedCallConfig.reuseUserOp, false, "reuseUserOp 2 incorrect");
        assertEq(decodedCallConfig.userAuctioneer, true, "userAuctioneer 2 incorrect");
        assertEq(decodedCallConfig.solverAuctioneer, false, "solverAuctioneer 2 incorrect");
        assertEq(decodedCallConfig.unknownAuctioneer, true, "unknownAuctioneer 2 incorrect");
        assertEq(decodedCallConfig.verifyCallChainHash, false, "verifyCallChainHash 2 incorrect");
        assertEq(decodedCallConfig.forwardReturnData, true, "forwardPreOpsReturnData 2 incorrect");
        assertEq(decodedCallConfig.requireFulfillment, false, "requireFulfillment 2 incorrect");   
        assertEq(decodedCallConfig.trustedOpHash, true, "trustedOpHash 2 incorrect");
        assertEq(decodedCallConfig.invertBidValue, false, "invertBidValue 2 incorrect");
        assertEq(decodedCallConfig.exPostBids, true, "exPostBids 2 incorrect");
        assertEq(decodedCallConfig.allowAllocateValueFailure, false, "allowAllocateValueFailure 2 incorrect");
    }

    function testConfigParameters() public view {
        uint32 encodedCallConfig = CallBits.encodeCallConfig(callConfig1);
        assertEq(encodedCallConfig.needsSequentialUserNonces(), false, "needsSequentialUserNonces 1 incorrect");
        assertEq(encodedCallConfig.needsSequentialDAppNonces(), true, "needsSequentialDAppNonces 1 incorrect");
        assertEq(encodedCallConfig.needsPreOpsCall(), false, "needsPreOpsCall 1 incorrect");
        assertEq(encodedCallConfig.needsPreOpsReturnData(), true, "needsPreOpsReturnData 1 incorrect");
        assertEq(encodedCallConfig.needsUserReturnData(), false, "needsUserReturnData 1 incorrect");
        assertEq(encodedCallConfig.needsDelegateUser(), true, "needsDelegateUser 1 incorrect");
        assertEq(encodedCallConfig.needsPreSolverCall(), false, "needsPreSolverCall 1 incorrect");
        assertEq(encodedCallConfig.needsPostSolverCall(), true, "needsPostSolverCall 1 incorrect");
        assertEq(encodedCallConfig.allowsZeroSolvers(), false, "allowsZeroSolvers 1 incorrect");
        assertEq(encodedCallConfig.allowsReuseUserOps(), true, "allowsReuseUserOps 1 incorrect");
        assertEq(encodedCallConfig.allowsUserAuctioneer(), false, "allowsUserAuctioneer 1 incorrect");
        assertEq(encodedCallConfig.allowsSolverAuctioneer(), true, "allowsSolverAuctioneer 1 incorrect");
        assertEq(encodedCallConfig.allowsUnknownAuctioneer(), false, "allowsUnknownAuctioneer 1 incorrect");
        assertEq(encodedCallConfig.verifyCallChainHash(), true, "verifyCallChainHash 1 incorrect");
        assertEq(encodedCallConfig.forwardReturnData(), false, "forwardPreOpsReturnData 1 incorrect");
        assertEq(encodedCallConfig.needsFulfillment(), true, "needsFulfillment 1 incorrect");
        assertEq(encodedCallConfig.allowsTrustedOpHash(), false, "allowsTrustedOpHash 1 incorrect");
        assertEq(encodedCallConfig.invertsBidValue(), true, "invertsBidValue 1 incorrect");
        assertEq(encodedCallConfig.exPostBids(), false, "exPostBids 1 incorrect");
        assertEq(encodedCallConfig.allowAllocateValueFailure(), true, "allowAllocateValueFailure 1 incorrect");
        

        encodedCallConfig = CallBits.encodeCallConfig(callConfig2);
        assertEq(encodedCallConfig.needsSequentialUserNonces(), true, "needsSequentialUserNonces 2 incorrect");
        assertEq(encodedCallConfig.needsSequentialDAppNonces(), false, "needsSequentialDAppNonces 2 incorrect");
        assertEq(encodedCallConfig.needsPreOpsCall(), true, "needsPreOpsCall 2 incorrect");
        assertEq(encodedCallConfig.needsPreOpsReturnData(), false, "needsPreOpsReturnData 2 incorrect");
        assertEq(encodedCallConfig.needsUserReturnData(), true, "needsUserReturnData 2 incorrect");
        assertEq(encodedCallConfig.needsDelegateUser(), false, "needsDelegateUser 2 incorrect");
        assertEq(encodedCallConfig.needsPreSolverCall(), true, "needsPreSolverCall 2 incorrect");
        assertEq(encodedCallConfig.needsPostSolverCall(), false, "needsPostSolverCall 2 incorrect");
        assertEq(encodedCallConfig.allowsZeroSolvers(), true, "allowsZeroSolvers 2 incorrect");
        assertEq(encodedCallConfig.allowsReuseUserOps(), false, "allowsReuseUserOps 2 incorrect");
        assertEq(encodedCallConfig.allowsUserAuctioneer(), true, "allowsUserAuctioneer 2 incorrect");
        assertEq(encodedCallConfig.allowsSolverAuctioneer(), false, "allowsSolverAuctioneer 2 incorrect");
        assertEq(encodedCallConfig.allowsUnknownAuctioneer(), true, "allowsUnknownAuctioneer 2 incorrect");
        assertEq(encodedCallConfig.verifyCallChainHash(), false, "verifyCallChainHash 2 incorrect");
        assertEq(encodedCallConfig.forwardReturnData(), true, "forwardPreOpsReturnData 2 incorrect");
        assertEq(encodedCallConfig.needsFulfillment(), false, "needsFulfillment 2 incorrect");
        assertEq(encodedCallConfig.allowsTrustedOpHash(), true, "allowsTrustedOpHash 2 incorrect");
        assertEq(encodedCallConfig.invertsBidValue(), false, "invertsBidValue 2 incorrect");
        assertEq(encodedCallConfig.exPostBids(), true, "exPostBids 2 incorrect");
        assertEq(encodedCallConfig.allowAllocateValueFailure(), false, "allowAllocateValueFailure 2 incorrect");
    }
}
