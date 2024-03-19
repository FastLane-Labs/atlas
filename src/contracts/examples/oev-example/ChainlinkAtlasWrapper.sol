//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/Test.sol"; //TODO remove

// A wrapper contract for a specific Chainlink price feed, used by Atlas to capture Oracle Extractable Value (OEV).
// Each MEV-generating protocol needs their own wrapper for each Chainlink price feed they use.
contract ChainlinkAtlasWrapper is Ownable {
    address public immutable ATLAS;
    IChainlinkFeed public immutable BASE_FEED; // Base Chainlink Feed
    IChainlinkDAppControl public immutable DAPP_CONTROL; // Chainlink Atlas DAppControl

    int256 public atlasLatestAnswer;
    uint256 public atlasLatestTimestamp;

    // Trusted ExecutionEnvironments
    mapping(address transmitter => bool trusted) public transmitters;

    error TransmitterNotTrusted(address transmitter);
    error InvalidTransmitMsgDataLength();
    error ObservationsNotOrdered();
    error AnswerMustBeAboveZero();
    error SignerVerificationFailed();
    error WithdrawETHFailed();

    event TransmitterStatusChanged(address indexed transmitter, bool trusted);
    event SignerStatusChanged(address indexed account, bool isSigner);

    constructor(address atlas, address baseChainlinkFeed, address _owner) {
        ATLAS = atlas;
        BASE_FEED = IChainlinkFeed(baseChainlinkFeed);
        DAPP_CONTROL = IChainlinkDAppControl(msg.sender); // Chainlink DAppControl is also wrapper factory

        _transferOwnership(_owner);
    }

    // Called by the contract which creates OEV when reading a price feed update.
    // If Atlas solvers have submitted a more recent answer than the base oracle's most recent answer,
    // the `atlasLatestAnswer` will be returned. Otherwise fallback to the base oracle's answer.
    function latestAnswer() public view returns (int256) {
        if (BASE_FEED.latestTimestamp() >= atlasLatestTimestamp) {
            return BASE_FEED.latestAnswer();
        } else {
            return atlasLatestAnswer;
        }
    }

    // Use this contract's latestTimestamp if more recent than base oracle's.
    // Otherwise fallback to base oracle's latestTimestamp
    function latestTimestamp() public view returns (uint256) {
        if (BASE_FEED.latestTimestamp() >= atlasLatestTimestamp) {
            return BASE_FEED.latestTimestamp();
        } else {
            return atlasLatestTimestamp;
        }
    }

    // Fallback to base oracle's latestRoundData, unless this contract's latestTimestamp and latestAnswer are more
    // recent, in which case return those values as well as the other round data from the base oracle.
    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = BASE_FEED.latestRoundData();
        if (updatedAt < atlasLatestTimestamp) {
            answer = atlasLatestAnswer;
            updatedAt = atlasLatestTimestamp;
        }
    }

    // Called by a trusted ExecutionEnvironment during an Atlas metacall
    // Returns address of this contract - used in allocateValueCall for OEV allocation
    function transmit(
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        external
        returns (address)
    {
        if (!transmitters[msg.sender]) revert TransmitterNotTrusted(msg.sender);

        int256 answer = _verifyTransmitData(report, rs, ss, rawVs);

        atlasLatestAnswer = answer;
        atlasLatestTimestamp = block.timestamp;

        return address(this);
    }

    // Verification checks for new transmit data
    function _verifyTransmitData(
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        internal
        view
        returns (int256)
    {
        ReportData memory r;
        (,, r.observations) = abi.decode(report, (bytes32, bytes32, int192[]));

        // Check observations are ordered, then take median observation
        for (uint256 i = 0; i < r.observations.length - 1; ++i) {
            bool inOrder = r.observations[i] <= r.observations[i + 1];
            if (!inOrder) revert ObservationsNotOrdered();
        }
        int192 median = r.observations[r.observations.length / 2];

        if (median <= 0) revert AnswerMustBeAboveZero();

        bool signersVerified =
            IChainlinkDAppControl(DAPP_CONTROL).verifyTransmitSigners(address(BASE_FEED), report, rs, ss, rawVs);
        if (!signersVerified) revert SignerVerificationFailed();

        return int256(median);
    }

    // ---------------------------------------------------- //
    //                     Owner Functions                  //
    // ---------------------------------------------------- //

    // Owner can add/remove trusted transmitters (ExecutionEnvironments)
    function setTransmitterStatus(address transmitter, bool trusted) external onlyOwner {
        transmitters[transmitter] = trusted;
        emit TransmitterStatusChanged(transmitter, trusted);
    }

    // Withdraw ETH OEV captured via Atlas solver bids
    function withdrawETH(address recipient) external onlyOwner {
        (bool success,) = recipient.call{ value: address(this).balance }("");
        if (!success) revert WithdrawETHFailed();
    }

    // Withdraw ERC20 OEV captured via Atlas solver bids
    function withdrawERC20(address token, address recipient) external onlyOwner {
        SafeERC20.safeTransfer(IERC20(token), recipient, IERC20(token).balanceOf(address(this)));
    }

    fallback() external payable { }
    receive() external payable { }
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

interface IChainlinkFeed {
    function latestAnswer() external view returns (int256);
    function latestTimestamp() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IChainlinkDAppControl {
    function verifyTransmitSigners(
        address baseChainlinkFeed,
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        external
        view
        returns (bool verified);
}
