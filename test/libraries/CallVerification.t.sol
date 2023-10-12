// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {CallVerification} from "../../src/contracts/libraries/CallVerification.sol";
import "../../src/contracts/types/UserCallTypes.sol";
import "../base/TestUtils.sol";

contract CallVerificationTest is Test {
    using CallVerification for UserOperation;
    using CallVerification for BidData[];

    function buildUserOperation() internal pure returns (UserOperation memory) {
        return UserOperation({
            from: address(0x1),
            to: address(0x0),
            deadline: 12,
            gas: 34,
            nonce: 56,
            maxFeePerGas: 78,
            value: 90,
            dapp: address(0x2),
            control: address(0x3),
            data: "data",
            signature: "signature"
        });
    }

    function builderSolverOperation() internal view returns (SolverOperation memory) {
        return SolverOperation({
            from: address(0x1),
            to: address(0x0),
            value: 12,
            gas: 34,
            maxFeePerGas: 78,
            nonce: 56,
            deadline: block.number + 2,
            solver: address(0x2),
            control: address(0x3),
            userOpHash: "userCallHash",
            bidToken: address(0x4),
            bidAmount: 5,
            data: "data",
            signature: "signature"
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
        this._testGetUserCallHash(buildUserOperation());
    }

    function _testGetUserCallHash(UserOperation calldata userOp) external {
        assertEq(userOp.getUserOperationHash(), keccak256(abi.encode(userOp)));
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
        UserOperation memory userOp = buildUserOperation();
        SolverOperation[] memory solverOps = new SolverOperation[](2);
        solverOps[0] = builderSolverOperation();
        solverOps[1] = builderSolverOperation();
        this._testGetCallChainHash(dConfig, userOp, solverOps);
    }

    function _testGetCallChainHash(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps
    ) external {
        bytes32 callChainHash = CallVerification.getCallChainHash(dConfig, userOp, solverOps);
        assertEq(
            callChainHash,
            TestUtils.computeCallChainHash(dConfig, userOp, solverOps),
            "callChainHash different to TestUtils reproduction"
        );
    }
}
