// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { AtlasVerification } from "../src/contracts/atlas/AtlasVerification.sol";
import { DAppConfig, DAppOperation } from "../src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../src/contracts/types/SolverCallTypes.sol";
import { ValidCallsResult } from "../src/contracts/types/ValidCallsTypes.sol";


contract AtlasVerificationTest is Test {

    function setUp() public {
    }

    function test_T() public {
        AtlasVerification atlasVerification = new AtlasVerification(address(0));

        DAppConfig memory config = DAppConfig({
            to: address(0),
            callConfig: 0,
            bidToken: address(0)
        });

        UserOperation memory userOp = UserOperation({
            from: address(0),
            to: address(0),
            value: 0,
            gas: 0,
            maxFeePerGas: 0,
            nonce: 0,
            deadline: 0,
            dapp: address(0),
            control: address(0),
            sessionKey: address(0),
            data: "",
            signature: ""
        });

        SolverOperation memory solverOp = SolverOperation({
            from: address(0),
            to: address(0),
            value: 0,
            gas: 0,
            maxFeePerGas: 0,
            deadline: 0,
            solver: address(0),
            control: address(0),
            userOpHash: "",
            bidToken: address(0),
            bidAmount: 0,
            data: "",
            signature: ""
        });

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;

        DAppOperation memory dappOp = DAppOperation({
            from: address(0),
            to: address(0),
            value: 0,
            gas: 0,
            maxFeePerGas: 0,
            nonce: 0,
            deadline: 0,
            control: address(0),
            bundler: address(0),
            userOpHash: "",
            callChainHash: "",
            signature: ""
        });

        uint256 msgValue = 0;
        address msgSender = address(0);
        bool isSimulation = false;
        
        vm.startPrank(address(0));

        ValidCallsResult validCallsResult;
        (solverOps, validCallsResult) = atlasVerification.validCalls(config, userOp, solverOps, dappOp, msgValue, msgSender, isSimulation);

        console.log("validCallsResult: %s", uint(validCallsResult));

        assertTrue(validCallsResult == ValidCallsResult.Valid, "validCallsResult should be Success");
    }

}
