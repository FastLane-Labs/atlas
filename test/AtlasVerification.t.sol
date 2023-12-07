// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";

import "../src/contracts/types/UserCallTypes.sol";
import "../src/contracts/types/SolverCallTypes.sol";
import "../src/contracts/types/DAppApprovalTypes.sol";

contract AtlasVerificationTest is Test {
    address constant ATLAS = address(0xA71A5);
    address constant ZERO_ADDRESS = address(0x00);

    AtlasVerification verification;

    function setUp() public {
        verification = new AtlasVerification(ATLAS);
    }

    function test_validCalls_invalidCaller() public {
        DAppConfig memory dConfig;
        UserOperation memory userOp;
        SolverOperation[] memory solverOps;
        DAppOperation memory dappOp;

        vm.expectRevert(AtlasVerification.InvalidCaller.selector);
        verification.validCalls(dConfig, userOp, solverOps, dappOp, ZERO_ADDRESS, 0, ZERO_ADDRESS, false);
    }
}
