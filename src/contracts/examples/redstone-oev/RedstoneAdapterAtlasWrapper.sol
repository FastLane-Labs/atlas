//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { MergedSinglePriceFeedAdapterWithoutRounds } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/MergedSinglePriceFeedAdapterWithoutRounds.sol";
import { AggregatorV2V3Interface } from "src/contracts/examples/oev-example/IChainlinkAtlasWrapper.sol";
import { IRedstoneAdapter } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol";
import "./RedstoneDAppControl.sol";

interface IAdapter {
    function getDataFeedIds() external view returns (bytes32[] memory);
    function getAuthorisedSignerIndex(address _receivedSigner) external view returns (uint8);
}

interface IFeed {
    function latestAnswer() external view returns (int256);
    function latestTimestamp() external view returns (uint256);
    function getPriceFeedAdapter() external view returns (IRedstoneAdapter);
}

contract RedstoneAdapterAtlasWrapper is Ownable, MergedSinglePriceFeedAdapterWithoutRounds {
    address public immutable ATLAS;
    address public immutable DAPP_CONTROL;

    address public immutable BASE_ADAPTER;
    address public immutable BASE_FEED;

    address[] public authorisedSigners;

    uint256 public BASE_FEED_DELAY = 4;

    error BaseAdapterHasNoDataFeed();
    error InvalidAuthorisedSigner();

    int256 public atlasAnswer;
    uint256 public atlasAnswerUpdatedAt;

    constructor(address atlas, address _owner, address _baseFeed) {
        ATLAS = atlas;
        DAPP_CONTROL = msg.sender;
        BASE_FEED = _baseFeed;
        BASE_ADAPTER = address(IFeed(_baseFeed).getPriceFeedAdapter());
        _transferOwnership(_owner);
        authorisedSigners.push(_owner);
    }

    function setBaseFeedDelay(uint256 _delay) external onlyOwner {
        BASE_FEED_DELAY = _delay;
    }

    function getAuthorisedSignerIndex(address _receivedSigner) public view virtual override returns (uint8) {
        for (uint8 i = 0; i < authorisedSigners.length; i++) {
            if (authorisedSigners[i] == _receivedSigner) {
                return i;
            }
        }
        revert InvalidAuthorisedSigner();
    }

    function requireAuthorisedUpdater(address updater) public view virtual override {
        getAuthorisedSignerIndex(updater);
    }

    function getDataFeedId() public view virtual override returns (bytes32 dataFeedId) {
        bytes32[] memory dataFeedIds = IAdapter(BASE_ADAPTER).getDataFeedIds();
        if (dataFeedIds.length == 0) {
            revert BaseAdapterHasNoDataFeed();
        }
        dataFeedId = dataFeedIds[0];
    }

    function addAuthorisedSigner(address _signer) external onlyOwner {
        authorisedSigners.push(_signer);
    }

    function removeAuthorisedSigner(address _signer) external onlyOwner {
        for (uint256 i = 0; i < authorisedSigners.length; i++) {
            if (authorisedSigners[i] == _signer) {
                authorisedSigners[i] = authorisedSigners[authorisedSigners.length - 1];
                authorisedSigners.pop();
                break;
            }
        }
    }

    function latestAnswer() public view virtual override returns (int256) {
        int256 baseAnswer = IFeed(BASE_FEED).latestAnswer();
        if (atlasAnswer == 0) {
            return baseAnswer;
        }
        uint256 baseLatestTimestamp = IFeed(BASE_FEED).latestTimestamp();

        if (atlasAnswerUpdatedAt > baseLatestTimestamp - BASE_FEED_DELAY) {
            return atlasAnswer;
        }
        return baseAnswer;
    }

    function latestTimestamp() public view virtual returns (uint256) {
        uint256 baseLatestTimestamp = IFeed(BASE_FEED).latestTimestamp();
        if (atlasAnswer == 0) {
            return baseLatestTimestamp;
        }
        if (atlasAnswerUpdatedAt > baseLatestTimestamp - BASE_FEED_DELAY) {
            return atlasAnswerUpdatedAt;
        }
        return baseLatestTimestamp;
    }
}
