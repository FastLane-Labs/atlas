// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "test/base/BaseTest.t.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";
import { UserOperationBuilder } from "test/base/builders/UserOperationBuilder.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { ExecutionEnvironment } from "src/contracts/atlas/ExecutionEnvironment.sol";
import { Sorter } from "src/contracts/helpers/Sorter.sol";
import { Simulator } from "src/contracts/helpers/Simulator.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { DAppOperation, DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/LockTypes.sol";

import { LibSort } from "solady/utils/LibSort.sol";

// These tests focus on the functions found in the Atlas.sol file
contract AtlasTest is BaseTest {

    function setUp_bidFindingIteration() public {
        // super.setUp();

        // vm.startPrank(payee);
        // simulator = new Simulator();

        // // Computes the addresses at which AtlasVerification will be deployed
        // address expectedAtlasAddr = vm.computeCreateAddress(payee, vm.getNonce(payee) + 1);
        // address expectedAtlasVerificationAddr = vm.computeCreateAddress(payee, vm.getNonce(payee) + 2);
        // bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedAtlasAddr, "AtlasFactory 1.0"));
        // ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedAtlasAddr);

        // atlas = new MockAtlas({
        //     _escrowDuration: 64,
        //     _verification: expectedAtlasVerificationAddr,
        //     _simulator: address(simulator),
        //     _executionTemplate: address(execEnvTemplate),
        //     _surchargeRecipient: payee
        // });
        // atlasVerification = new AtlasVerification(address(atlas));
        // simulator.setAtlas(address(atlas));
        // sorter = new Sorter(address(atlas));
        // vm.stopPrank();
    }

    function test_bidFindingIteration_sortingOrder() public {
        // Test order of bidsAndIndices after insertionSort

        // 3 items. [200, 0, 100] --> [0, 100, 200] 
        uint256[] memory bidsAndIndices = new uint256[](3);
        bidsAndIndices[0] = 100;
        bidsAndIndices[1] = 0;
        bidsAndIndices[2] = 300;

        LibSort.insertionSort(bidsAndIndices);
        assertEq(bidsAndIndices[0], 0);
        assertEq(bidsAndIndices[1], 100);
        assertEq(bidsAndIndices[2], 300);

        // 1 item. [100] --> [100]
        bidsAndIndices = new uint256[](1);
        bidsAndIndices[0] = 100;

        LibSort.insertionSort(bidsAndIndices);
        assertEq(bidsAndIndices[0], 100);

        // 2 items. [100, 0] --> [0, 100]
        bidsAndIndices = new uint256[](2);
        bidsAndIndices[0] = 100;
        bidsAndIndices[1] = 0;

        LibSort.insertionSort(bidsAndIndices);
        assertEq(bidsAndIndices[0], 0);
        assertEq(bidsAndIndices[1], 100);
    }

    function test_bidFindingIteration_packBidAndIndex() public {
        uint256 bid = 12345;
        uint256 index = 2;

        uint256 packed = _packBidAndIndex(bid, index);
        (uint256 unpackedBid, uint256 unpackedIndex) = _unpackBidAndIndex(packed);
        assertEq(unpackedBid, bid);
        assertEq(unpackedIndex, index);

        bid = type(uint240).max - 1;
        index = 7;

        packed = _packBidAndIndex(bid, index);
        (unpackedBid, unpackedIndex) = _unpackBidAndIndex(packed);
        assertEq(unpackedBid, bid);
        assertEq(unpackedIndex, index);

        bid = 0;
        index = 1;

        packed = _packBidAndIndex(bid, index);
        (unpackedBid, unpackedIndex) = _unpackBidAndIndex(packed);
        assertEq(unpackedBid, bid);
        assertEq(unpackedIndex, index);

        bid = 1;
        index = 0;

        packed = _packBidAndIndex(bid, index);
        (unpackedBid, unpackedIndex) = _unpackBidAndIndex(packed);
        assertEq(unpackedBid, bid);
        assertEq(unpackedIndex, index);
    }


    // Packs bid and index into a single uint256, replicates logic used in `_bidFindingIteration()`
    function _packBidAndIndex(uint256 bid, uint256 index) internal pure returns (uint256) {
        return uint256(bid << 16 | uint16(index));
    }

    // Unpacks bid and index from a single uint256, replicates logic used in `_bidFindingIteration()`
    function _unpackBidAndIndex(uint256 packed) internal pure returns (uint256 bid, uint256 index) {
        // bidAmountFound = (bidsAndIndices[i] >> BITS_FOR_INDEX) & FIRST_240_BITS_MASK;
        bid = (packed >> 16) & uint256(0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

        // uint256 solverOpsIndex = bidsAndIndices[i] & FIRST_16_BITS_MASK;
        index = packed & uint256(0xFFFF);
    }
}

// MockAtlas exposes Atlas' internal functions for testing
contract MockAtlas is Atlas {
    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient,
        address _executionTemplate
    ) 
        Atlas(_escrowDuration, _verification, _simulator, _surchargeRecipient, _executionTemplate) 
    { }

    function bidFindingIteration(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        bytes memory returnData,
        Context memory ctx
    ) public returns (bool auctionWon, Context memory) {
        return _bidFindingIteration(dConfig, userOp, solverOps, returnData, ctx);
    }
}