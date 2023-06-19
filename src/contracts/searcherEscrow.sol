//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IFactory } from "../interfaces/IFactory.sol";
import { ISearcherEscrow } from "../interfaces/ISearcherEscrow.sol";
import { IHandler } from "../interfaces/IHandler.sol";

import { FastLaneDataTypes, SearcherOutcome } from "./DataTypes.sol";
import { ThogLock } from "./ThogLock.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

contract FastLaneEscrow is FastLaneDataTypes, ISearcherEscrow, ThogLock, EIP712 {
    using ECDSA for bytes32;

    uint256 immutable public chainId;
    address immutable public factory;
    uint32 immutable public escrowDuration;

    uint256 private _activeGasRebate;
    address private _activeHandler;

    address private _pendingSearcher;
    SearcherEscrow private _pendingEscrowUpdate;
    ValueTracker private _pendingValueTracker;

    // NOTE: these storage vars / maps should only be accessible by *signed* searcher transactions
    // and only once per searcher per block (to avoid user-searcher collaborative exploits)
    // EOA Address => searcher escrow data
    mapping(address => SearcherEscrow) private _escrowData;

    // track searcher tx hashes to avoid replays... imperfect solution tho
    mapping(bytes32 => bool) private _hashes;

    constructor(uint32 escrowDurationFromFactory) ThogLock(address(this), msg.sender) EIP712("ProtoCallHandler", "0.0.1") {
        chainId = block.chainid;
        factory = msg.sender;
        escrowDuration = escrowDurationFromFactory; //TODO: get this as input from factory w/o breaking linearization
    }

    function setEscrowThogLock(
        address activeHandler,
        Lock memory mLock
    ) external {
        require(msg.sender == factory, "ERR-E07 InvalidSender");
        require(_activeHandler == address(0), "ERR-E11 ExistingHandler");
        require(_keyCode == 0, "ERR-E12 KeyCodeTampering");
        require(_baseLock == BaseLock.Unlocked, "ERR-E13 NotUnlocked");

        _baseLock = BaseLock.Locked;
        _activeHandler = activeHandler;
        _sLock = mLock;

        _pendingValueTracker = ValueTracker({
            starting: uint128(address(this).balance),
            transferred: 0
        });
    }

    function releaseEscrowThogLock(
        uint256 handlerKeyCode,
        uint256 searcherCallCount
    ) external returns (uint256 gasRebate, uint256 valueReturn) {
        // address(this) == escrowAddress
        require(msg.sender == _activeHandler, "ERR-T03 InvalidCaller");
        require(_baseLock == BaseLock.Locked, "ERR-T04 AlreadyUnlocked");

        Lock memory mLock = _sLock;

        // first check that the searcher call counter matches
        require(mLock._alpha == mLock._omega, "ERR-T04 MissingKeys");

        // check that the handler's count also matches
        // TODO: probably unnecessary
        require(searcherCallCount == mLock._omega, "ERR-T04 MissingCalls");

        // check that the handler's key matches the escrow key
        require(handlerKeyCode == _keyCode, "ERR-T06 InvalidKey1");

        // then check that they match the lockCode
        require(handlerKeyCode == mLock._lockCode, "ERR-T06 InvalidKey2");

        // then call the factory to set up final verification 
        // TODO: might be unnecessary
        IFactory(_factoryAddress).initReleaseFactoryThogLock(handlerKeyCode);

        // forward the correct value back to the handler for distribution
        // to the user
        ValueTracker memory valueTracker = _pendingValueTracker;

        valueReturn = (address(this).balance - valueTracker.starting) + valueTracker.transferred;
        gasRebate = _activeGasRebate;

        SafeTransferLib.safeTransferETH(
            msg.sender, // verified above that msg.sender = handler
            valueReturn + gasRebate
        );

        // _baseLock = BaseLock.Unlocked;
        delete _baseLock; // TODO: ^ see if there's a gas refund dif here on enums, result should be the same
        delete _keyCode;
        delete _sLock;
        delete _activeGasRebate;
        delete _activeHandler;
        delete _pendingValueTracker;
    }

    function update(
        uint256 gasWaterMark,
        uint256 result,
        IHandler.SearcherCall calldata searcherCall
    ) external {
        require(msg.sender == _activeHandler, "ERR-E17 InvalidSender");
        require(searcherCall.metaTx.from == _pendingSearcher, "ERR-E18 InvalidSignature");
    
        delete _pendingSearcher; 

        SearcherEscrow memory escrowUpdate = _pendingEscrowUpdate;

        uint256 gasRebate;

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
        _activeGasRebate += gasRebate > escrowUpdate.total ? escrowUpdate.total : gasRebate;
                
        escrowUpdate.total -= uint128(gasRebate); 

        // NOTE: some nonce updates may still be needed so run this even
        // if the gasRebate = 0
        _escrowData[searcherCall.metaTx.from] = escrowUpdate;
        
        delete _pendingEscrowUpdate;
    }

    function verify(
        bytes32 userCallHash,
        bool callSuccess,
        IHandler.SearcherCall calldata searcherCall
    ) external returns (uint256 result, uint256 gasLimit) {

        require(msg.sender == _activeHandler, "ERR-SE00 InvalidSender");

        // TODO: lots of testing on bitwise conditions to make sure that
        // pendingSearcher is always cleared out before every verify
        require(_pendingSearcher == address(0), "ERR-SE01 ExistingSearcher");

        _turnKeySafe(searcherCall);

        if (_verifySignature(searcherCall.metaTx, searcherCall.signature)) {
            uint256 gasRebate;
            bool forwardValue;
            (result, gasRebate, gasLimit, forwardValue) = _verifyCallData(userCallHash, callSuccess, searcherCall);
            
            _activeGasRebate += gasRebate;
            // _pendingSearcher = searcherCall.metaTx.from; // moved to verifyCallData

            // NOTE: searchers should be informed that using a value parameter 
            // in their transactions will be extremely gas expensive for them
            if (forwardValue) {
                SafeTransferLib.safeTransferETH(
                    msg.sender, // verified above that msg.sender = handler
                    searcherCall.metaTx.value
                );
            }
        
        } else {
            (result, gasLimit) = (1 << uint256(SearcherOutcome.InvalidSignature), 0);
        }
    }

    // TODO: make a more thorough version of this
    function _verifySignature(
        IHandler.SearcherMetaTx calldata metaTx, 
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
        IHandler.BidData[] calldata bids
    ) internal pure returns(bool validBid) {
        // NOTE: this should only occur after the searcher's signature on the bidsHash is verified

        validBid = keccak256(abi.encode(bids)) != bidsHash;
    }

    // TODO: break this up into something readable
    function _verifyCallData(
        bytes32 userCallHash,
        bool callSuccess,
        IHandler.SearcherCall calldata searcherCall
    ) internal returns (uint256 result, uint256 gasRebate, uint256 gasLimit, bool forwardValue) {

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
            _pendingSearcher = searcherCall.metaTx.from; 
            _pendingEscrowUpdate = searcherEscrow;

            result |= 1 << uint256(SearcherOutcome.PendingUpdate);
        }

        forwardValue = (searcherCall.metaTx.value > 0) && ((result >>1) == 0);
    }

    receive() external payable {
        if (gasleft() > 3_000) {
            if (msg.sender == _activeHandler && msg.sender != address(0)) {
                
                // If not in middle of processing a searcher call, credit
                // the value to the user via the value tracker
                if (_pendingSearcher == address(0)) {
                    _pendingValueTracker.transferred += uint128(msg.value);

                // If there's a pending searcher, that means this is a
                // refund from handler for the searcher due to a call failure
                } else {
                    _escrowData[_pendingSearcher].total += uint128(msg.value);
                }
            
            } else {
                revert(); // no untracked balance transfers plz
            }
        
        } else {
            revert(); // no untracked balance transfers plz
        }
    }

    fallback() external payable {}
}