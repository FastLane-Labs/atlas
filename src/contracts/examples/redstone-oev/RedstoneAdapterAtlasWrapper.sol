//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { MergedSinglePriceFeedAdapterWithoutRounds } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/MergedSinglePriceFeedAdapterWithoutRounds.sol";
import { AggregatorV2V3Interface } from "src/contracts/examples/oev-example/IChainlinkAtlasWrapper.sol";
import { IRedstoneAdapter } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol";
import "./RedstoneDAppControl.sol";

interface IAdapterWithRounds {
    function getDataFeedIds() external view returns (bytes32[] memory);
    function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256);
    function getTimestampsFromLatestUpdate() external view returns (uint128 dataTimestamp, uint128 blockTimestamp);
    function getRoundDataFromAdapter(bytes32, uint256) external view returns (uint256, uint128, uint128);
}

interface IFeed {
    function getPriceFeedAdapter() external view returns (IRedstoneAdapter);
    function getDataFeedId() external view returns (bytes32);
    function latestAnswer() external view returns (int256);
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
    function latestRound() external view returns (uint80);
    function getRoundData(uint80) external view returns (uint80,int256,uint256,uint256,uint80);
}

contract RedstoneAdapterAtlasWrapper is Ownable, MergedSinglePriceFeedAdapterWithoutRounds {
    address public immutable ATLAS;
    address public immutable DAPP_CONTROL;

    address public immutable BASE_ADAPTER;
    address public immutable BASE_FEED;

    uint256 public constant MAX_HISTORICAL_FETCH_ITERATIONS = 5;

    address[] public authorisedSigners;

    uint256 public BASE_FEED_DELAY = 4; //seconds

    error BaseAdapterHasNoDataFeed();
    error InvalidAuthorisedSigner();
    error BaseAdapterDoesNotSupportHistoricalData();
    error CannotFetchHistoricalData();

    constructor(address atlas, address _owner, address _baseFeed) {
        uint80 latestRound = IFeed(_baseFeed).latestRound();
        // check to see if earlier rounds are supported
        // this will revert if the base adapter does not support earlier rounds(historical data)
        IFeed(_baseFeed).getRoundData(latestRound - 1); 

        ATLAS = atlas;
        DAPP_CONTROL = msg.sender;
        BASE_FEED = _baseFeed;
        BASE_ADAPTER = address(IFeed(_baseFeed).getPriceFeedAdapter());
        _transferOwnership(_owner);
    }

    function setBaseFeedDelay(uint256 _delay) external onlyOwner {
        BASE_FEED_DELAY = _delay;
    }

    function getAuthorisedSignerIndex(address _receivedSigner) public view virtual override returns (uint8) {
        if (authorisedSigners.length == 0) {
            return 0;
        }
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
        return IFeed(BASE_FEED).getDataFeedId();
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

    function requireMinIntervalBetweenUpdatesPassed() private view {
        uint256 currentBlockTimestamp = getBlockTimestamp();
        uint256 blockTimestampFromLatestUpdate = getBlockTimestampFromLatestUpdate();
        uint256 minIntervalBetweenUpdates = getMinIntervalBetweenUpdates();
        if (currentBlockTimestamp < blockTimestampFromLatestUpdate + minIntervalBetweenUpdates) {
            revert MinIntervalBetweenUpdatesHasNotPassedYet(
                currentBlockTimestamp,
                blockTimestampFromLatestUpdate,
                minIntervalBetweenUpdates
            );
        }
    }

    function latestAnswer() public view virtual override returns (int256) {
        bytes32 dataFeedId = getDataFeedId();
        (,uint256 atlasLatestBlockTimestamp) = getTimestampsFromLatestUpdate();
        uint256 atlasAnswer = getValueForDataFeed(dataFeedId);

        uint80 roundId = IFeed(BASE_FEED).latestRound();

        uint256 numIter;
        for (;;){
            (uint256 baseValue,, uint128 baseBlockTimestamp) = IAdapterWithRounds(BASE_ADAPTER).getRoundDataFromAdapter(dataFeedId, roundId);
            if (atlasLatestBlockTimestamp >= baseBlockTimestamp){
                return int256(atlasAnswer);
            }
            if (block.timestamp - baseBlockTimestamp >= BASE_FEED_DELAY){
                return int256(baseValue);
            }

            unchecked {
                numIter++;
                roundId--;
            }

            if (numIter > MAX_HISTORICAL_FETCH_ITERATIONS){
                revert CannotFetchHistoricalData();
            }
        }
        // unreachable
        return 0;
    }

    function latestTimestamp() public view virtual returns (uint256) {
        bytes32 dataFeedId = getDataFeedId();
        (,uint256 atlasLatestBlockTimestamp) = getTimestampsFromLatestUpdate();

        uint80 roundId = IFeed(BASE_FEED).latestRound();

        uint256 numIter;
        for (;;){
            (,, uint128 baseBlockTimestamp) = IAdapterWithRounds(BASE_ADAPTER).getRoundDataFromAdapter(dataFeedId, roundId);
            if (atlasLatestBlockTimestamp >= baseBlockTimestamp){
                return atlasLatestBlockTimestamp;
            }
            if (block.timestamp - baseBlockTimestamp >= BASE_FEED_DELAY){
                return uint256(baseBlockTimestamp);
            }

            unchecked {
                numIter++;
                roundId--;
            }

            if (numIter > MAX_HISTORICAL_FETCH_ITERATIONS){
                revert CannotFetchHistoricalData();
            }
        }
        // unreachable
        return 0;
    }

    function latestRoundData()
        public
        view
        override
        virtual
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
        {
        roundId = latestRound();
        answer = latestAnswer();

        uint256 latestTStamp = latestTimestamp();

        // These values are equal after chainlink’s OCR update
        startedAt = latestTStamp;
        updatedAt = latestTStamp;

        // We want to be compatible with Chainlink's interface
        // And in our case the roundId is always equal to answeredInRound
        answeredInRound = roundId;
    }
}
