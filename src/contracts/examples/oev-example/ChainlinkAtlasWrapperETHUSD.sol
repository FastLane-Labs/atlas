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

    mapping(address transmitter => bool trusted) public transmitters;

    error TransmitterNotTrusted(address transmitter);
    error InvalidTransmitData();

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
    function transmit(
        bytes calldata _report,
        bytes32[] calldata _rs,
        bytes32[] calldata _ss,
        bytes32 _rawVs
    )
        external
    {
        if (!transmitters[msg.sender]) revert TransmitterNotTrusted(msg.sender);

        (bool dataVerified, int256 answer) = _verifyTransmitData(_report, _rs, _ss, _rawVs);
        if (!dataVerified) revert InvalidTransmitData(); // TODO move to more specific reverts in verify func

        atlasLatestAnswer = answer;
        atlasLatestTimestamp = block.timestamp;
    }

    // Verifies
    function _verifyTransmitData(
        bytes calldata _report,
        bytes32[] calldata _rs,
        bytes32[] calldata _ss,
        bytes32 _rawVs
    )
        internal
        returns (bool, int256)
    {
        // TODO implement based on Chainlink Aggregator transmit function logic
    }

    // Owner can add/remove trusted transmitters
    function setTransmitterStatus(address transmitter, bool trusted) external onlyOwner {
        transmitters[transmitter] = trusted;
    }
}

// -----------------------------------------------
// Structs and interface for Chainlink Aggregator
// -----------------------------------------------

struct ReportData {
    HotVars hotVars; // Only read from storage once
    bytes observers; // ith element is the index of the ith observer
    int192[] observations; // ith element is the ith observation
    bytes vs; // jth element is the v component of the jth signature
    bytes32 rawReportContext;
}

struct HotVars {
    // Provides 128 bits of security against 2nd pre-image attacks, but only
    // 64 bits against collisions. This is acceptable, since a malicious owner has
    // easier way of messing up the protocol than to find hash collisions.
    bytes16 latestConfigDigest;
    uint40 latestEpochAndRound; // 32 most sig bits for epoch, 8 least sig bits for round
    // Current bound assumed on number of faulty/dishonest oracles participating
    // in the protocol, this value is referred to as f in the design
    uint8 threshold;
    // Chainlink Aggregators expose a roundId to consumers. The offchain reporting
    // protocol does not use this id anywhere. We increment it whenever a new
    // transmission is made to provide callers with contiguous ids for successive
    // reports.
    uint32 latestAggregatorRoundId;
}

interface IChainlinkAggregator {
    function latestAnswer() external view returns (int256);
    function latestTimestamp() external view returns (uint256);
}
