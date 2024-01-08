// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { CallBits } from "../../src/contracts/libraries/CallBits.sol";
import "../../src/contracts/types/UserCallTypes.sol";
import "../base/TestUtils.sol";

contract CallBitsTest is Test {
    using CallBits for uint32;

    CallConfig callConfig1;
    CallConfig callConfig2;

    function setUp() public {
        callConfig1 = CallConfig({
            sequenced: true,
            requirePreOps: false,
            trackPreOpsReturnData: true,
            trackUserReturnData: false,
            delegateUser: true,
            preSolver: false,
            postSolver: true,
            requirePostOps: false,
            zeroSolvers: true,
            reuseUserOp: false,
            userAuctioneer: true,
            solverAuctioneer: false,
            unknownAuctioneer: true,
            verifyCallChainHash: false,
            forwardReturnData: true,
            requireFulfillment: false
        });

        callConfig2 = CallConfig({
            sequenced: !callConfig1.sequenced,
            requirePreOps: !callConfig1.requirePreOps,
            trackPreOpsReturnData: !callConfig1.trackPreOpsReturnData,
            trackUserReturnData: !callConfig1.trackUserReturnData,
            delegateUser: !callConfig1.delegateUser,
            preSolver: !callConfig1.preSolver,
            postSolver: !callConfig1.postSolver,
            requirePostOps: !callConfig1.requirePostOps,
            zeroSolvers: !callConfig1.zeroSolvers,
            reuseUserOp: !callConfig1.reuseUserOp,
            userAuctioneer: !callConfig1.userAuctioneer,
            solverAuctioneer: !callConfig1.solverAuctioneer,
            unknownAuctioneer: !callConfig1.unknownAuctioneer,
            verifyCallChainHash: !callConfig1.verifyCallChainHash,
            forwardReturnData: !callConfig1.forwardReturnData,
            requireFulfillment: !callConfig1.requireFulfillment
        });
    }

    function testEncodeCallConfig() public {
        string memory expectedBitMapString = "00000000000000000101010101010101";
        assertEq(
            TestUtils.uint32ToBinaryString(CallBits.encodeCallConfig(callConfig1)),
            expectedBitMapString,
            "callConfig1 incorrect"
        );

        expectedBitMapString = "00000000000000001010101010101010";
        assertEq(
            TestUtils.uint32ToBinaryString(CallBits.encodeCallConfig(callConfig2)),
            expectedBitMapString,
            "callConfig2 incorrect"
        );
    }

    function testDecodeCallConfig() public {
        uint32 encodedCallConfig = CallBits.encodeCallConfig(callConfig1);
        CallConfig memory decodedCallConfig = encodedCallConfig.decodeCallConfig();
        assertEq(decodedCallConfig.sequenced, true, "sequenced 1 incorrect");
        assertEq(decodedCallConfig.requirePreOps, false, "requirePreOps 1 incorrect");
        assertEq(decodedCallConfig.trackPreOpsReturnData, true, "trackPreOpsReturnData 1 incorrect");
        assertEq(decodedCallConfig.trackUserReturnData, false, "trackUserReturnData 1 incorrect");
        assertEq(decodedCallConfig.delegateUser, true, "delegateUser 1 incorrect");
        assertEq(decodedCallConfig.preSolver, false, "preSolver 1 incorrect");
        assertEq(decodedCallConfig.postSolver, true, "postSolver 1 incorrect");
        assertEq(decodedCallConfig.requirePostOps, false, "requirePostOps 1 incorrect");
        assertEq(decodedCallConfig.zeroSolvers, true, "zeroSolvers 1 incorrect");
        assertEq(decodedCallConfig.reuseUserOp, false, "reuseUserOp 1 incorrect");
        assertEq(decodedCallConfig.userAuctioneer, true, "userAuctioneer 1 incorrect");
        assertEq(decodedCallConfig.solverAuctioneer, false, "solverAuctioneer 1 incorrect");
        assertEq(decodedCallConfig.unknownAuctioneer, true, "unknownAuctioneer 1 incorrect");
        assertEq(decodedCallConfig.verifyCallChainHash, false, "verifyCallChainHash 1 incorrect");
        assertEq(decodedCallConfig.forwardReturnData, true, "forwardPreOpsReturnData 1 incorrect");
        assertEq(decodedCallConfig.requireFulfillment, false, "requireFulfillment 1 incorrect");

        encodedCallConfig = CallBits.encodeCallConfig(callConfig2);
        decodedCallConfig = encodedCallConfig.decodeCallConfig();
        assertEq(decodedCallConfig.sequenced, false, "sequenced 2 incorrect");
        assertEq(decodedCallConfig.requirePreOps, true, "requirePreOps 2 incorrect");
        assertEq(decodedCallConfig.trackPreOpsReturnData, false, "trackPreOpsReturnData 2 incorrect");
        assertEq(decodedCallConfig.trackUserReturnData, true, "trackUserReturnData 2 incorrect");
        assertEq(decodedCallConfig.delegateUser, false, "delegateUser 2 incorrect");
        assertEq(decodedCallConfig.preSolver, true, "preSolver 2 incorrect");
        assertEq(decodedCallConfig.postSolver, false, "postSolver 2 incorrect");
        assertEq(decodedCallConfig.requirePostOps, true, "requirePostOps 2 incorrect");
        assertEq(decodedCallConfig.zeroSolvers, false, "zeroSolvers 2 incorrect");
        assertEq(decodedCallConfig.reuseUserOp, true, "reuseUserOp 2 incorrect");
        assertEq(decodedCallConfig.userAuctioneer, false, "userAuctioneer 2 incorrect");
        assertEq(decodedCallConfig.solverAuctioneer, true, "solverAuctioneer 2 incorrect");
        assertEq(decodedCallConfig.unknownAuctioneer, false, "unknownAuctioneer 2 incorrect");
        assertEq(decodedCallConfig.verifyCallChainHash, true, "verifyCallChainHash 2 incorrect");
        assertEq(decodedCallConfig.forwardReturnData, false, "forwardPreOpsReturnData 2 incorrect");
        assertEq(decodedCallConfig.requireFulfillment, true, "requireFulfillment 2 incorrect");
    }

    function testConfigParameters() public {
        uint32 encodedCallConfig = CallBits.encodeCallConfig(callConfig1);
        assertEq(encodedCallConfig.needsSequencedNonces(), true, "needsSequencedNonces 1 incorrect");
        assertEq(encodedCallConfig.needsPreOpsCall(), false, "needsPreOpsCall 1 incorrect");
        assertEq(encodedCallConfig.needsPreOpsReturnData(), true, "needsPreOpsReturnData 1 incorrect");
        assertEq(encodedCallConfig.needsUserReturnData(), false, "needsUserReturnData 1 incorrect");
        assertEq(encodedCallConfig.needsDelegateUser(), true, "needsDelegateUser 1 incorrect");
        assertEq(encodedCallConfig.needsPreSolver(), false, "needsPreSolver 1 incorrect");
        assertEq(encodedCallConfig.needsSolverPostCall(), true, "needsSolverPostCall 1 incorrect");
        assertEq(encodedCallConfig.needsPostOpsCall(), false, "needsPostOpsCall 1 incorrect");
        assertEq(encodedCallConfig.allowsZeroSolvers(), true, "allowsZeroSolvers 1 incorrect");
        assertEq(encodedCallConfig.allowsReuseUserOps(), false, "allowsReuseUserOps 1 incorrect");
        assertEq(encodedCallConfig.allowsUserAuctioneer(), true, "allowsUserAuctioneer 1 incorrect");
        assertEq(encodedCallConfig.allowsSolverAuctioneer(), false, "allowsSolverAuctioneer 1 incorrect");
        assertEq(encodedCallConfig.allowsUnknownAuctioneer(), true, "allowsUnknownAuctioneer 1 incorrect");
        assertEq(encodedCallConfig.verifyCallChainHash(), false, "verifyCallChainHash 1 incorrect");
        assertEq(encodedCallConfig.forwardReturnData(), true, "forwardPreOpsReturnData 1 incorrect");
        assertEq(encodedCallConfig.needsFulfillment(), false, "needsFulfillment 1 incorrect");
        encodedCallConfig = CallBits.encodeCallConfig(callConfig2);
        assertEq(encodedCallConfig.needsSequencedNonces(), false, "needsSequencedNonces 2 incorrect");
        assertEq(encodedCallConfig.needsPreOpsCall(), true, "needsPreOpsCall 2 incorrect");
        assertEq(encodedCallConfig.needsPreOpsReturnData(), false, "needsPreOpsReturnData 2 incorrect");
        assertEq(encodedCallConfig.needsUserReturnData(), true, "needsUserReturnData 2 incorrect");
        assertEq(encodedCallConfig.needsDelegateUser(), false, "needsDelegateUser 2 incorrect");
        assertEq(encodedCallConfig.needsPreSolver(), true, "needsPreSolver 2 incorrect");
        assertEq(encodedCallConfig.needsSolverPostCall(), false, "needsSolverPostCall 2 incorrect");
        assertEq(encodedCallConfig.needsPostOpsCall(), true, "needsPostOpsCall 2 incorrect");
        assertEq(encodedCallConfig.allowsZeroSolvers(), false, "allowsZeroSolvers 2 incorrect");
        assertEq(encodedCallConfig.allowsReuseUserOps(), true, "allowsReuseUserOps 2 incorrect");
        assertEq(encodedCallConfig.allowsUserAuctioneer(), false, "allowsUserAuctioneer 2 incorrect");
        assertEq(encodedCallConfig.allowsSolverAuctioneer(), true, "allowsSolverAuctioneer 2 incorrect");
        assertEq(encodedCallConfig.allowsUnknownAuctioneer(), false, "allowsUnknownAuctioneer 2 incorrect");
        assertEq(encodedCallConfig.verifyCallChainHash(), true, "verifyCallChainHash 2 incorrect");
        assertEq(encodedCallConfig.forwardReturnData(), false, "forwardPreOpsReturnData 2 incorrect");
        assertEq(encodedCallConfig.needsFulfillment(), true, "needsFulfillment 2 incorrect");
    }
}
