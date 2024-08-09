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
   
}
