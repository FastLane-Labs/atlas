//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

// A wrapper contract for Chainlink's ETH/USD price feed, used by Atlas to capture Oracle Extractable Value (OEV).
// Each asset price feed needs its own wrapper contract.

contract ChainlinkAtlasWrapperETHUSD is Ownable {
    address public immutable ATLAS;
    IChainlinkAggregator public immutable BASE_SOURCE; // Base Chainlink Aggregator

    int256 public atlasLatestAnswer;
    uint256 public atlasLatestTimestamp;

    mapping(address submitter => bool trusted) public trustedSubmitters;

    error SubmitterNotTrusted(address submitter);

    constructor(address atlas, address _baseChainlinkAggregator) {
        ATLAS = atlas;
        BASE_SOURCE = IChainlinkAggregator(_baseChainlinkAggregator);
    }

    // Called by the contract which creates OEV when reading a price feed update.
    // If Atlas solvers have submitted a more recent answer than the base oracle's most recent answer,
    // the `atlasLatestAnswer` will be returned. Otherwise fallback to the base oracle's answer.
    function latestAnswer() public view returns (int256) {
        if (BASE_SOURCE.latestTimestamp() >= atlasLatestTimestamp) {
            return BASE_SOURCE.latestAnswer();
        } else {
            return atlasLatestAnswer;
        }
    }

    // Called by a trusted ExecutionEnvironment during an Atlas metacall
    function submitAtlasAnswer(int256 answer) external {
        if (!trustedSubmitters[msg.sender]) revert SubmitterNotTrusted(msg.sender);
        atlasLatestAnswer = answer;
        atlasLatestTimestamp = block.timestamp;
    }

    function setSubmitterTrustStatus(address submitter, bool trusted) external onlyOwner {
        trustedSubmitters[submitter] = trusted;
    }
}

interface IChainlinkAggregator {
    function latestAnswer() external view returns (int256);
    function latestTimestamp() external view returns (uint256);
}
