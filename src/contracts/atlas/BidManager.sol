//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IAtlas} from "../interfaces/IAtlas.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import {Sorter} from "./Sorter.sol";

import "../types/CallTypes.sol";

struct StoredSearcherOperation {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    uint256 maxFeePerGas; // maxFeePerGas searcher is willing to pay.  This goes to validator, not protocol or user
    uint64 deadline;

    bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
    bytes32 controlCodeHash; // ProtocolControl.codehash
    
    bytes32 auctionKey;
    uint8 auctionIndex;
    uint128 escrowed;

    BidData[] searcherBid;

    bytes data;
}

struct SearcherBids {
    uint64 wins;
    uint64 attempts;
    uint8 floor;
    uint8 ceiling;
    StoredSearcherOperation[256] ops;
}

struct BidPointer {
    address from;
    uint8 searcherIndex;
    uint8 auctionIndex;
    uint8 rebidIndex;
    uint64 deadline;
}

// TODO: Use bitwise to enable multiple AuctionDuration types
enum DurationType {
    ManualUser, // User must end auction
    ManualProtocol, // ProtocolControl sig must end auction
    ManualOther, // A specified address must end auction
    ManualSearcher, // A searcher can end the auction
    ManualAny, // Anyone can end the auction
    SpecificBlock, // End on a specific block
    SpecificTime, // End at a specific timestamp (ill advised)
    DurationBlock, // End after a specific number of blocks have passed
    DurationTime // End after a specific amount of time has passed (ill advised)
}

struct AuctionDuration {
    DurationType dType;
    address caller;
    uint64 value;
}

struct Auction {
    uint64 reputation;
    bool active;
    uint8 bidCount;
    address executionEnvironment;
    AuctionDuration duration;
    UserMetaTx userOperation;
}

// Designed for a magical world in which concerns over gas cost 
// don't lead to a dependency on centralized infrastructure...
contract BidManager is Sorter {

    uint256 immutable public maxSearcherBids; // 32
    uint64 immutable public reputationScalingFactor; // 1_000
    uint64 constant public BASE_REPUTATION = 10_000;
    uint64 constant public STARTING_REPUTATION = 5_000;

    uint64 public highestReputation;

    // searcherMetaTx.from => SearcherBids
    mapping(address => SearcherBids) internal _searchers;

    // keccak256(auctionKey, searcherMetaTx.from) => BidPointer
    mapping(bytes32 => BidPointer) internal _active;

    // auctionKey => Auction
    mapping(bytes32 => Auction) internal _auctions;

    // keccak256(auctionKey, bidIndex) => BidPointer
    // NOTE: A fill in for an array
    mapping(bytes32 => BidPointer) internal _bids;

    constructor(uint256 _maxSearcherBids, uint64 _reputationScalingFactor) Sorter(msg.sender, msg.sender) {
        maxSearcherBids = _maxSearcherBids;
        reputationScalingFactor = _reputationScalingFactor;
    }


    function startAuction(UserCall calldata userCall, AuctionDuration calldata duration) external {
        require(userCall.to == atlas, "ERR-BM001 InvalidUserTo");
        require(IAtlas(atlas).testUserCall(userCall), "ERR-BM002 UserCallFailure");

        bytes32 auctionKey = _getAuctionKey(userCall.metaTx);

        require(_auctions[auctionKey].executionEnvironment == address(0), "ERR-BM003 DuplicateUserCall");

        address executionEnvironment = IAtlas(atlas).getExecutionEnvironment(userCall, userCall.metaTx.control);

        _auctions[auctionKey] = Auction({
            reputation: STARTING_REPUTATION,
            active: true,
            bidCount: 0,
            executionEnvironment: executionEnvironment,
            duration: duration,
            userOperation: userCall.metaTx
        });
    }

    function submitBid(bytes32 auctionKey, SearcherCall calldata searcherCall) external {
        SearcherMetaTx memory searcherOp = searcherCall.metaTx;
        address searcherFrom = searcherOp.from;

        require(msg.sender == searcherFrom, "ERR-BM005 InvalidCaller");

        Auction memory auction = _auctions[auctionKey];

        require(auction.active, "ERR-BM006 InactiveAuction");
        require(_isValidSearcherTx(searcherCall), "ERR-BM007 InvalidSearcherTx");

        // TODO: consider calling execution environment instead? need to consider security implications
        ProtocolCall memory protocolCall = IProtocolControl(auction.userOperation.control).getProtocolCall();

        (bool invalid, uint128 escrowedGas) = IEscrow(atlas).verifySearcherStorage(protocolCall, searcherCall);
        if (invalid) {
            return; // graceful return to preserve nonce increments and prevent replay
        }

        // TODO: More safety checks

        // note: need to start floor at 1
        BidPointer memory ptr = _active[keccak256(abi.encodePacked(auctionKey, searcherFrom))];
     
        // Check if this is a new bid
        unchecked {
            if (ptr.rebidIndex != 0) {
                ++ptr.rebidIndex;

                // can't shorten the deadline on a rebid
                uint64 newDeadline = uint64(searcherOp.deadline);
                if (ptr.deadline > newDeadline) {
                    return;
                } else if (ptr.deadline < newDeadline) {
                    ptr.deadline = newDeadline;
                }

                // TODO: enforce that bid amount goes up *AND* that the call is still successful
                // (Do not allow a searcher to overwrite a successful call w/ a failing call)
                // NOTE: Might need to remove rebidding entirely

            } else {
                ptr = BidPointer({
                    from: searcherFrom,
                    searcherIndex: ++_searchers[searcherFrom].ceiling,
                    auctionIndex: ++_auctions[auctionKey].bidCount,
                    rebidIndex: 1,
                    deadline: uint64(searcherOp.deadline)
                });
            }
        }

        _bids[keccak256(abi.encodePacked(auctionKey, ptr.auctionIndex))] = ptr;
        
        _searchers[searcherFrom].ops[ptr.searcherIndex] = StoredSearcherOperation({
            from: searcherFrom,
            to: searcherOp.to,
            gas: searcherOp.gas,
            value: searcherOp.value,
            nonce: searcherOp.nonce,
            maxFeePerGas: searcherOp.maxFeePerGas,
            deadline: uint64(searcherOp.deadline),
            userCallHash: searcherOp.userCallHash,
            controlCodeHash: searcherOp.controlCodeHash,
            auctionKey: auctionKey,
            auctionIndex: ptr.auctionIndex,
            escrowed: escrowedGas,
            searcherBid: searcherCall.bids,
            data: searcherOp.data
        });
    }

    function getAuctionKey(UserMetaTx calldata userMetaTx) external pure returns (bytes32 auctionKey) {
        auctionKey = keccak256(abi.encode(userMetaTx));
    }

    function _getAuctionKey(UserMetaTx memory userMetaTx) internal pure returns (bytes32 auctionKey) {
        auctionKey = keccak256(abi.encode(userMetaTx));
    }

    // TODO: finish
    function _isValidSearcherTx(SearcherCall calldata) internal pure returns (bool valid) {
        valid = true;
    }
}