//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { MergedSinglePriceFeedAdapterWithoutRounds } from "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/MergedSinglePriceFeedAdapterWithoutRounds.sol";
import { IRedstoneAdapter } from "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol";
import {
    AggregatorV2V3Interface
} from "src/contracts/examples/oev-example/IChainlinkAtlasWrapper.sol";
import "./RedstoneDAppControl.sol";

contract RedstoneAdapterAtlasWrapper is Ownable, MergedSinglePriceFeedAdapterWithoutRounds {
    address public immutable ATLAS;
    address public immutable DAPP_CONTROL;

    address public immutable BASE_ADAPTER;
    address public immutable BASE_FEED;

    uint public BASE_FEED_DELAY = 4;

    error BaseAdapterHasNoDataFeed();

    int256 public atlasAnswer;
    uint256 public atlasAnswerUpdatedAt;

    constructor(address atlas, address _owner, address _baseAdapter, address _baseFeed) {
        ATLAS = atlas;
        DAPP_CONTROL = msg.sender;
        BASE_ADAPTER = _baseAdapter;
        BASE_FEED = _baseFeed;
        _transferOwnership(_owner);
    }

    function setBaseFeedDelay(uint _delay) external onlyOwner {
        BASE_FEED_DELAY = _delay;
    }

    function getAuthorisedSignerIndex(address _receivedSigner) public view virtual override returns (uint8) {
        return IAdapter(BASE_ADAPTER).getAuthorisedSignerIndex(_receivedSigner);
    }

    function getDataFeedId() public view virtual override returns (bytes32 dataFeedId){
        bytes32[] memory dataFeedIds = IRedstoneAdapter(BASE_ADAPTER).getDataFeedIds();
        if (dataFeedIds.length == 0) {
            revert BaseAdapterHasNoDataFeed();
        }
        dataFeedId = dataFeedIds[0];
    }

    //called by Atlas `UserOperation` 
    function setValues(int256 _answer, uint256 _updatedAt)
        external
        onlyOwner
    {
        atlasAnswer = _answer;
        atlasAnswerUpdatedAt = _updatedAt;
    }

    function latestAnswer() public view virtual override returns (int256) {
        int256 baseAnswer = IAdapter(BASE_ADAPTER).latestAnswer();
        if (atlasAnswer == 0){
            return baseAnswer;
        }
        uint256 baseLatestTimestamp = IAdapter(BASE_ADAPTER).latestTimestamp();

        if (atlasAnswerUpdatedAt > baseLatestTimestamp - BASE_FEED_DELAY) {
            return atlasAnswer;
        }
        return baseAnswer;
    }

    function latestTimestamp() public view virtual returns (uint256) {
        uint256 baseLatestTimestamp = IAdapter(BASE_ADAPTER).latestTimestamp();
        if (atlasAnswer == 0){
            return baseLatestTimestamp;
        }
        if (atlasAnswerUpdatedAt > baseLatestTimestamp - BASE_FEED_DELAY) {
            return atlasAnswerUpdatedAt;
        }
        return baseLatestTimestamp;   
    }
}

interface IAdapter {
    function getAuthorisedSignerIndex(address _receivedSigner) external view returns (uint8);
    function latestAnswer() external view returns (int256);
    function latestTimestamp() external view returns (uint256);
}