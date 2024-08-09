// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "src/contracts/examples/redstone-oev/RedstoneAdapterAtlasWrapper.sol";
import "src/contracts/examples/redstone-oev/RedstoneDAppControl.sol";
import { BaseTest } from "test/base/BaseTest.t.sol";

contract RedstoneDAppControlTest is BaseTest {
    RedstoneDAppControl dappControl;
    RedstoneAdapterAtlasWrapper wrapper;
    address baseFeedAddress = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;
    uint32 dataPointValue = 666999;

    function setUp() public override {
        super.setUp();
       
        console.log("base feed", baseFeedAddress);
        console.log("base adapter", address(IFeed(baseFeedAddress).getPriceFeedAdapter()));
        vm.startPrank(governanceEOA);
        dappControl = new RedstoneDAppControl(address(atlas));
        wrapper = RedstoneAdapterAtlasWrapper(dappControl.createNewAtlasAdapter(baseFeedAddress));
        vm.stopPrank();
    }

    function testDeployDAppControlAndCreateWrapper() public {
        int256 baseAnswer = IFeed(baseFeedAddress).latestAnswer();
        console.log("base answer", uint256(baseAnswer));

        testUpdateDataFeedsValues();

        require(IFeed(baseFeedAddress).latestAnswer() == baseAnswer, "base feed answer should not change");
        int256 answer = wrapper.latestAnswer();

        require(uint256(answer) == uint256(dataPointValue), "answer should be equal to dataPointValue");

        (uint80 roundId, int256 ansround, uint256 startedAt, uint256 updatedAt,) = wrapper.latestRoundData();
        require(roundId == 1);
        require(uint256(ansround) == uint256(dataPointValue));

        console.log("startedAt", startedAt);
        console.log("updatedAt", updatedAt);

        (,,uint256 baseStartedAt, uint256 baseUpdatedAt,) = IFeed(baseFeedAddress).latestRoundData();
        console.log("base startedAt", baseStartedAt);
        console.log("base updatedAt", baseUpdatedAt);

        (uint128 dataTimestamp, uint128 blockTimestamp) = IAdapter(address(IFeed(baseFeedAddress).getPriceFeedAdapter())).getTimestampsFromLatestUpdate();
        console.log("dataTimestamp", uint256(dataTimestamp));
        console.log("blockTimestamp", uint256(blockTimestamp));

        (uint128 dataTimestampWrapper, uint128 blockTimestampWrapper) = IAdapter(address(wrapper)).getTimestampsFromLatestUpdate();
        console.log("dataTimestampWrapper", uint256(dataTimestampWrapper));
        console.log("blockTimestampWrapper", uint256(blockTimestampWrapper));
    }
   
    function testUpdateDataFeedsValues() public {
        bytes32 dataFeed = IFeed(baseFeedAddress).getDataFeedId();
        uint48 timestamp = uint48(block.timestamp * 1000);
        uint32 valueSize = 4;
        uint24 dataPointsCount = 1;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(governancePK, keccak256(abi.encodePacked(dataFeed, dataPointValue, timestamp, valueSize, dataPointsCount)));
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory payload = abi.encodePacked(
            // *** SIGNED DATA PACKAGES ***
            // 1st data package
            // - 1st data point
            // -- feed identifier
            dataFeed,               // 32 bytes
            // -- value
            dataPointValue,         // 4 bytes
            // - more data points
            // ...
            // - timestamp (milliseconds)
            timestamp,              // 6 bytes
            // - value size
            valueSize,              // 4 bytes
            // - data points count
            dataPointsCount,        // 3 bytes
            // - signature
            signature, // 65 bytes

            // more data packages
            // ...

            // data packages count
            uint16(1),              // 2 bytes

            // *** UNSIGNED METADATA ***
            // - message
            uint256(666),           // 32 bytes
            // - message size
            uint24(32),             // 3 bytes
            // - red stone marker
            hex"000002ed57011e0000"    // 9 bytes
        );

        bytes memory call = abi.encodeCall(wrapper.updateDataFeedsValues, (timestamp));
        call = bytes.concat(call, payload);

        vm.prank(address(0x123));
        (bool success,) = address(wrapper).call(call);

        require(success, "Payload attachment failed");
    }
}
