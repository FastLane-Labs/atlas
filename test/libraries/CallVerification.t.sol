// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {CallVerification} from "../../src/contracts/libraries/CallVerification.sol";
import "../../src/contracts/types/CallTypes.sol";

contract CallVerificationTest is Test {
    using CallVerification for UserCall;
    using CallVerification for BidData[];

    function buildUserCall() internal pure returns (UserCall memory) {
        return UserCall({
            from: address(0x1),
            to: address(0x2),
            deadline: 12,
            gas: 34,
            nonce: 56,
            maxFeePerGas: 78,
            value: 90,
            control: address(0x3),
            data: "data"
        });
    }

    function builderSolverCall() internal pure returns (SolverCall memory) {
        return SolverCall({
            from: address(0x1),
            to: address(0x2),
            value: 12,
            gas: 34,
            nonce: 56,
            maxFeePerGas: 78,
            userOpHash: "userCallHash",
            controlCodeHash: "controlCodeHash",
            bidsHash: "bidsHash",
            data: "data"
        });
    }

    function buildBidData(uint256 n) internal pure returns (BidData[] memory) {
        BidData[] memory bidData = new BidData[](n);
        for (uint256 i = 0; i < n; i++) {
            bidData[i] = BidData({token: address(0x1), bidAmount: i});
        }
        return bidData;
    }

    function testGetUserCallHash() public {
        this._testGetUserCallHash(buildUserCall());
    }

    function _testGetUserCallHash(UserCall calldata uCall) external {
        assertEq(uCall.getUserOperationHash(), keccak256(abi.encode(uCall)));
    }

    function testGetBidsHash() public {
        // 1 bid
        BidData[] memory bidData = buildBidData(1);
        assertEq(bidData.getBidsHash(), keccak256(abi.encode(bidData)));

        // multiple bids
        bidData = buildBidData(3);
        assertEq(bidData.getBidsHash(), keccak256(abi.encode(bidData)));
    }

    function testGetCallChainHash() public {
        DAppConfig memory dConfig = DAppConfig({to: address(0x1), callConfig: 1});
        UserCall memory uCall = buildUserCall();
        SolverOperation[] memory solverOps = new SolverOperation[](2);
        solverOps[0] = SolverOperation({
            to: address(0x2),
            call: builderSolverCall(),
            signature: "signature1",
            bids: buildBidData(1)
        });
        solverOps[1] = SolverOperation({
            to: address(0x3),
            call: builderSolverCall(),
            signature: "signature2",
            bids: buildBidData(2)
        });
        this._testGetCallChainHash(dConfig, uCall, solverOps);
    }

    function _testGetCallChainHash(
        DAppConfig calldata dConfig,
        UserCall calldata uCall,
        SolverOperation[] calldata solverOps
    ) external {
        bytes32 expectedCallChainHash = 0x69c0833b2f37f7a0cb7d040aaa3f4654d841ebf21e6781b530a9c978d0c8cf09;
        bytes32 callChainHash = CallVerification.getCallChainHash(dConfig, uCall, solverOps);
        assertEq(callChainHash, expectedCallChainHash);
    }
}
