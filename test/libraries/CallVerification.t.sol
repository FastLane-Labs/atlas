// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {CallVerification} from "../../src/contracts/libraries/CallVerification.sol";
import "../../src/contracts/types/CallTypes.sol";

contract CallVerificationTest is Test {
    using CallVerification for UserMetaTx;
    using CallVerification for BidData[];

    function buildUserMetaTx() internal pure returns (UserMetaTx memory) {
        return UserMetaTx({
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

    function builderSearcherMetaTx() internal pure returns (SearcherMetaTx memory) {
        return SearcherMetaTx({
            from: address(0x1),
            to: address(0x2),
            value: 12,
            gas: 34,
            nonce: 56,
            maxFeePerGas: 78,
            userCallHash: "userCallHash",
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
        this._testGetUserCallHash(buildUserMetaTx());
    }

    function _testGetUserCallHash(UserMetaTx calldata userMetaTx) external {
        assertEq(userMetaTx.getUserCallHash(), keccak256(abi.encode(userMetaTx)));
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
        ProtocolCall memory protocolCall = ProtocolCall({to: address(0x1), callConfig: 1});
        UserMetaTx memory userMetaTx = buildUserMetaTx();
        SearcherCall[] memory searcherCalls = new SearcherCall[](2);
        searcherCalls[0] = SearcherCall({
            to: address(0x2),
            metaTx: builderSearcherMetaTx(),
            signature: "signature1",
            bids: buildBidData(1)
        });
        searcherCalls[1] = SearcherCall({
            to: address(0x3),
            metaTx: builderSearcherMetaTx(),
            signature: "signature2",
            bids: buildBidData(2)
        });
        this._testGetCallChainHash(protocolCall, userMetaTx, searcherCalls);
    }

    function _testGetCallChainHash(
        ProtocolCall calldata protocolCall,
        UserMetaTx calldata userMetaTx,
        SearcherCall[] calldata searcherCalls
    ) external {
        bytes32 expectedCallChainHash = 0x69c0833b2f37f7a0cb7d040aaa3f4654d841ebf21e6781b530a9c978d0c8cf09;
        bytes32 callChainHash = CallVerification.getCallChainHash(protocolCall, userMetaTx, searcherCalls);
        assertEq(callChainHash, expectedCallChainHash);
    }
}
