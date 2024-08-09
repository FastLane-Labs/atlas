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

    function setUp() public override {
        super.setUp();
       
        console.log("base feed", baseFeedAddress);
        console.logBytes32(IFeedx(baseFeedAddress).getDataFeedId());
        console.log("base adapter", address(IFeed(baseFeedAddress).getPriceFeedAdapter()));
        vm.startPrank(governanceEOA);
        dappControl = new RedstoneDAppControl(address(atlas));
        wrapper = RedstoneAdapterAtlasWrapper(dappControl.createNewAtlasAdapter(baseFeedAddress));
        vm.stopPrank();
    }

    function testDeployDAppControlAndCreateWrapper() public {
        int256 latestAnswer = wrapper.latestAnswer();

        require(latestAnswer != 0, "Latest answer should not be zero");

        vm.prank(address(0x9876));
        (
            uint80 roundId,
            int256 answer,
            ,,
            uint80 answeredInRound
        ) = wrapper.latestRoundData();

        require(answer != 0, "Answer should not be zero");
        require(roundId > 0, "Round ID should be greater than zero");
        require(answeredInRound == roundId, "Answered in round should match round ID");
    }

    function pushOracleUpdate() internal {
        uint256 dataPackagesTimestamp = block.timestamp;

        uint256 additionalValue = 123456789; 

        bytes memory calldataPayload = abi.encodeWithSelector(
            wrapper.updateDataFeedsValues.selector, 
            dataPackagesTimestamp, 
            additionalValue
        );

        vm.prank(address(0x9876)); 
        (bool success,) = address(wrapper).call(calldataPayload);
        require(success, "Oracle update failed");
    }
   
    function testUpdateDataFeedsValues() public {
        bytes32 dataFeed = IFeedx(baseFeedAddress).getDataFeedId();
        uint32 dataPointValue = 666999;
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

        vm.prank(governanceEOA);
        (bool success,) = address(wrapper).call(call);

        require(success, "Payload attachment failed");
    }
}
