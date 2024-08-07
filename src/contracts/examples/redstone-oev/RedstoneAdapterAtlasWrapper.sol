//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { RedstoneAdapterBase } from "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/RedstoneAdapterBase.sol";
import { IRedstoneAdapter } from "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol";
import {
    AggregatorV2V3Interface
} from "src/contracts/examples/oev-example/IChainlinkAtlasWrapper.sol";

contract RedstoneAdapterAtlasWrapper is Ownable, RedstoneAdapterBase {
    address public immutable ATLAS;
    IRedstoneAdapter public BASE_ADAPTER;
    AggregatorV2V3Interface public BASE_FEED;

    constructor(address atlas, address baseAdapter, address _owner) {
        ATLAS = atlas;
        BASE_ADAPTER = IRedstoneAdapter(baseAdapter);
        //DAPP_CONTROL = IChainlinkDAppControl(msg.sender); // Chainlink DAppControl is also wrapper factory

        _transferOwnership(_owner);
    }

    function _validateAndUpdateDataFeedsValues(bytes32[] memory dataFeedIdsArray, uint256[] memory values) internal virtual override{

    }

    function getAuthorisedSignerIndex(address receivedSigner) public view virtual override returns (uint8) {

    }

    function getDataFeedIds() public view virtual override returns (bytes32[] memory){

    }

    function getValueForDataFeedUnsafe(bytes32 dataFeedId) public view virtual override returns (uint256) {

    }

    // ---------------------------------------------------- //
    //           Chainlink Pass-through Functions           //
    // ---------------------------------------------------- //

    // Called by the contract which creates OEV when reading a price feed update.
    // If Atlas solvers have submitted a more recent answer than the base oracle's most recent answer,
    // the `atlasLatestAnswer` will be returned. Otherwise fallback to the base oracle's answer.
    function latestAnswer() public view returns (int256) {
        // if (BASE_FEED.latestTimestamp() >= atlasLatestTimestamp) {
        //     return BASE_FEED.latestAnswer();
        // }

        // return atlasLatestAnswer;
        return BASE_FEED.latestAnswer();
    }

    // Use this contract's latestTimestamp if more recent than base oracle's.
    // Otherwise fallback to base oracle's latestTimestamp
    function latestTimestamp() public view returns (uint256) {
        // uint256 baseFeedLatestTimestamp = BASE_FEED.latestTimestamp();
        // if (baseFeedLatestTimestamp >= atlasLatestTimestamp) {
        //     return baseFeedLatestTimestamp;
        // }

        // return atlasLatestTimestamp;
        return BASE_FEED.latestTimestamp();
    }
    
    // Fallback to base oracle's latestRoundData, unless this contract's `latestTimestamp` and `latestAnswer` are more
    // recent, in which case return those values as well as the other round data from the base oracle.
    // NOTE: This may break some integrations as it implies a `roundId` has multiple answers (the canonical answer from
    // the base feed, and the `atlasLatestAnswer` if more recent), which deviates from the expected behaviour of the
    // base Chainlink feeds. Be aware of this tradeoff when integrating ChainlinkAtlasWrappers as your price feed.
    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // (roundId, answer, startedAt, updatedAt, answeredInRound) = BASE_FEED.latestRoundData();
        // if (updatedAt < atlasLatestTimestamp) {
        //     answer = atlasLatestAnswer;
        //     updatedAt = atlasLatestTimestamp;
        // }
        return BASE_FEED.latestRoundData();
    }
}