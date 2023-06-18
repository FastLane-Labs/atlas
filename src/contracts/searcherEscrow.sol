//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { FastLaneDataTypes } from "./DataTypes.sol";
import { FastLaneErrorsEvents } from "./Emissions.sol";
import { ThogLock } from "./ThogLock.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

contract FastLaneEscrow is FastLaneErrorsEvents, FastLaneDataTypes, ThogLock, EIP712 {
    using ECDSA for bytes32;

    struct SearcherEscrow {
        uint128 total;
        uint128 escrowed;
        uint64 availableOn; // block.number when funds are available.  
        uint64 lastAccessed;
        uint32 nonce; // EOA nonce.
    }

    uint256 immutable public chainId;
    address immutable public factory;

    address private _activeHandler;

    address private _currentUserTo;
    bytes32 private _pendingSearcherKey;
    SearcherEscrow private _pendingEscrowUpdate;

    // NOTE: these storage vars / maps should only be accessible by *signed* searcher transactions
    // and only once per searcher per block (to avoid user-searcher collaborative exploits)
    // EOA Address => searcher escrow data
    mapping(address => SearcherEscrow) private _escrowData;

    // track searcher tx hashes to avoid replays... imperfect solution tho
    mapping(bytes32 => bool) private _hashes;

    constructor() ThogLock(address(this), msg.sender) EIP712("ProtoCallHandler", "0.0.1") {
        chainId = block.chainid;
        factory = msg.sender;
    }

    function setUserTo(address currentUserTo) external {
        
        require(msg.sender == factory, "ERR-E07 InvalidSender");
        require(_baseLockStatus() == BaseLock.Unlocked, "ERR-E08 Not Unlocked");
        require(_currentUserTo == address(0), "ERR-E09 TargetAlreadyExists");
        
        _currentUserTo = currentUserTo;
    }

    function update(
        uint256 gasWaterMark,
        uint256 result,
        SearcherCall calldata searcherCall
    ) external returns (uint256 gasRebate) {
        require(msg.sender == _activeHandler, "ERR-E17 InvalidSender");
        require(keccak256(searcherCall.signature) == _pendingSearcherKey, "ERR-E18 InvalidSignature");
    
        delete _pendingSearcherKey; 

        SearcherEscrow memory escrowUpdate = _pendingEscrowUpdate;

        // TODO: clean up code / make it readable
        if (
            !(result & _EXECUTION_REFUND == 0) ||
            !(result & _FULL_REFUND == 0)
        ) {
            gasRebate = (100 + SEARCHER_GAS_BUFFER) * (
                (tx.gasprice * GWEI * (gasWaterMark - gasleft() + (searcherCall.metaTx.data.length * 16))) + searcherCall.metaTx.value
            ) / 100;
        
        } else if (
            // TODO: figure out fair system for these
            !(result & _EXTERNAL_REFUND == 0)
        ) {
            gasRebate = (100 + SEARCHER_GAS_BUFFER) * (
                (tx.gasprice * GWEI * ((searcherCall.metaTx.data.length * 16))) + searcherCall.metaTx.value
            ) / 100;
        
        } else if (
            !(result & _CALLDATA_REFUND == 0)
        ) {
            gasRebate = (100 + SEARCHER_GAS_BUFFER) * (
                (tx.gasprice * GWEI * ((searcherCall.metaTx.data.length * 16))) + searcherCall.metaTx.value
            ) / 100;
        }

        // make sure we don't underflow 
        // TODO: measure frequency of this. 
        gasRebate = gasRebate > escrowUpdate.total ? escrowUpdate.total : gasRebate;
                
        escrowUpdate.total -= uint128(gasRebate); // TODO: add in some underflow handling

        // NOTE: some nonce updates may still be needed so run this even
        // if the gasRebate = 0
        _escrowData[searcherCall.metaTx.from] = escrowUpdate;
        
        delete _pendingEscrowUpdate;
    }

    function verify(
        bytes32 userCallHash,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) external returns (uint256, uint256, uint256) {

        _turnKeySafe(searcherCall);

        if (!_verifySignature(searcherCall.metaTx, searcherCall.signature)) {
            return (1 << uint256(SearcherOutcome.InvalidSignature), 0, 0);
        
        } else {
            return _verifyCallData(userCallHash, callSuccess, searcherCall);
        }
    }

    // TODO: make a more thorough version of this
    function _verifySignature(
        SearcherMetaTx calldata metaTx, 
        bytes calldata signature
    ) internal view returns (bool) {
        
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _TYPE_HASH, 
                    metaTx.from, 
                    metaTx.to, 
                    metaTx.value, 
                    metaTx.gas, 
                    metaTx.nonce,
                    metaTx.userCallHash,
                    metaTx.maxFeePerGas,
                    metaTx.bidsHash,
                    keccak256(metaTx.data)
                )
            )
        ).recover(signature);
        
        return signer == metaTx.from;
    }

    function _verifyBids(
        bytes32 bidsHash,
        BidData[] calldata bids
    ) internal pure returns(bool validBid) {
        // NOTE: this should only occur after the searcher's signature on the bidsHash is verified

        validBid = keccak256(abi.encode(bids)) != bidsHash;
    }

    // TODO: break this up into something readable
    function _verifyCallData(
        bytes32 userCallHash,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) internal returns (uint256 result, uint256 gasRebate, uint256 gasLimit) {

        if (callSuccess) {
            result |= 1 << uint256(SearcherOutcome.NotWinner);
        }

        if (userCallHash != searcherCall.metaTx.userCallHash) {
            result |= 1 << uint256(SearcherOutcome.InvalidUserHash);
        }

        bytes32 searcherHash = keccak256(searcherCall.signature);
        
        if (_hashes[searcherHash]) {
            result |= 1 << uint256(SearcherOutcome.AlreadyExecuted);
        } else {
            _hashes[searcherHash] = true;
        }

        SearcherEscrow memory searcherEscrow = _escrowData[searcherCall.metaTx.from];
        
        if (searcherCall.metaTx.nonce < uint256(searcherEscrow.nonce)) {
            result |= 1 << uint256(SearcherOutcome.InvalidNonceUnder);

        } else if (searcherCall.metaTx.nonce > uint256(searcherEscrow.nonce)) {
            result |= 1 << uint256(SearcherOutcome.InvalidNonceOver);

            // TODO: reconsider the jump up for gapped nonces? Intent is to mitigate dmg 
            // potential inflicted by a hostile searcher/builder. 
            searcherEscrow.nonce = uint32(searcherCall.metaTx.nonce + 1); 

        } else {
            ++searcherEscrow.nonce;
        }

        if (searcherEscrow.lastAccessed >= uint64(block.number)) {
            result |= 1 << uint256(SearcherOutcome.PerBlockLimit);
        } else {
            searcherEscrow.lastAccessed = uint64(block.number);
        }

        if (!_verifyBids(searcherCall.metaTx.bidsHash, searcherCall.bids)) {
            result |= 1 << uint256(SearcherOutcome.InvalidBidsHash);
        }

        gasLimit = (100 + SEARCHER_GAS_BUFFER) * (
            (
                searcherCall.metaTx.data.length * 16
            ) + (
                searcherCall.metaTx.gas < SEARCHER_GAS_LIMIT ? searcherCall.metaTx.gas : SEARCHER_GAS_LIMIT
            )
        ) / 100 ; 

        // see if searcher's escrow can afford tx gascost + tx value
        if ((tx.gasprice * GWEI * gasLimit) + searcherCall.metaTx.value < searcherEscrow.total - searcherEscrow.escrowed) {
            // charge searcher for calldata so that we can avoid vampire attacks from searcher onto user
            //return (SearcherOutcome.InsufficientEscrow, searcherCall.metaTx.data.length * 16);
            
            result |= 1 << uint256(SearcherOutcome.InsufficientEscrow);
        }

        // check for early gas refund after ruling out a NO_REFUND case
        if (
            !(result & _NO_REFUND == 0) && 
            (result & _CALLDATA_REFUND == 0)
        ) {
        
            // gasVariable is an early refund for calldata
            // TODO: make readable
            gasRebate = (
                (
                    tx.gasprice * GWEI * searcherCall.metaTx.data.length * 16
            ) > (
                    searcherEscrow.total - searcherEscrow.escrowed
                )
            ) ? (
                    searcherEscrow.total - searcherEscrow.escrowed 
            ) : (
                    tx.gasprice * GWEI * searcherCall.metaTx.data.length * 16
            ) ;

            searcherEscrow.total -= uint128(gasRebate);

            // preemptively update storage map
            // Only update SearcherEscrow if transaction is valid and not a replay
            _escrowData[searcherCall.metaTx.from] = searcherEscrow;

            result |= 1 << uint256(SearcherOutcome.UpdateCompleted);
            result |= 1 << uint256(SearcherOutcome.BlockExecution);
        
        // TODO: test gas using > instead of bitwise since the outcomes are 
        // directionally aligned along this spectrum
        } else if (
            !(result & _NO_NONCE_UPDATE == 0) &&
            (result & _BLOCK_VALID_EXECUTION == 0)
        ) {
            _escrowData[searcherCall.metaTx.from] = searcherEscrow;

            result |= 1 << uint256(SearcherOutcome.UpdateCompleted);
            result |= 1 << uint256(SearcherOutcome.BlockExecution);
        
        } else {
            // store for easier access post-execution
            // wtb transient storage <3
            _pendingSearcherKey = keccak256(searcherCall.signature); 
            _pendingEscrowUpdate = searcherEscrow;

            result |= 1 << uint256(SearcherOutcome.PendingUpdate);
        }
    }
}