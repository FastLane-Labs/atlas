//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISearcherEscrow } from "../interfaces/ISearcherEscrow.sol";
import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import { SafetyChecks } from "./SafetyChecks.sol";
import { SearcherExecution } from "./SearcherExecution.sol";
import { FastLaneDataTypes } from "../libraries/DataTypes.sol";
import { FastLaneErrorsEvents } from "./Emissions.sol";

import {
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    BidData,
    SearcherSafety,
    StagingCall,
    ExecutionPhase,
    EscrowKey,
    PayeeData,
    UserCall
} from "../libraries/DataTypes.sol";

contract FastLaneEscrow is SafetyChecks, SearcherExecution, FastLaneDataTypes, ISearcherEscrow, EIP712 {
    using ECDSA for bytes32;

    uint32 immutable public escrowDuration;

    ValueTracker private _pendingValueTracker;

    // NOTE: these storage vars / maps should only be accessible by *signed* searcher transactions
    // and only once per searcher per block (to avoid user-searcher collaborative exploits)
    // EOA Address => searcher escrow data
    mapping(address => SearcherEscrow) private _escrowData;

    // track searcher tx hashes to avoid replays... imperfect solution tho
    mapping(bytes32 => bool) private _hashes;

    constructor(
        uint32 escrowDurationFromFactory
    ) SafetyChecks(msg.sender) EIP712("ProtoCallHandler", "0.0.1") 
    {
        escrowDuration = escrowDurationFromFactory; 
    }

    function executeSearcherCall(
        bytes32 targetHash,
        bytes32 userCallHash,
        uint256 gasWaterMark,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) external returns (bool) {

        (uint256 result, uint256 gasLimit, SearcherEscrow memory searcherEscrow) = _verify(
            targetHash,
            userCallHash,
            callSuccess,
            searcherCall
        );

        result = _searcherCallPreCheck(
            result, 
            gasWaterMark,
            tx.gasprice,
            searcherCall.metaTx.maxFeePerGas,
            callSuccess
        );

        // If there are no errors, attempt to execute
        // NOTE: the lowest bit is a tracker (PendingUpdate) and can be ignored
        bool executed;

        if ((result >>1) == 0) {
            executed = true;
            result |= (
                1 << uint256(_searcherCallExecutor(gasLimit, searcherCall)) |
                1 << uint256(SearcherOutcome.ExecutionCompleted)
            );
        }

        _update(searcherEscrow, gasWaterMark, result, searcherCall);

        if (
            !callSuccess && (result & 1 << uint256(SearcherOutcome.ExecutionCompleted) != 0)
        ) { 
            // first successful searcher call that paid what it bid
            if (result & 1 << uint256(SearcherOutcome.Success) != 0) {
                callSuccess = true;
                // flag the escrow key to initiate payments
                // TODO: make this more robust?
                _escrowKey.makingPayments = true; 
            }
        }

        // emit event
        emit SearcherTxResult(
            searcherCall.metaTx.to,
            searcherCall.metaTx.from,
            executed,
            callSuccess,
            executed ? searcherEscrow.nonce - 1 : searcherEscrow.nonce,
            result
        );

        return callSuccess;
    }

    function executePayments(
        uint256 protocolShare,
        BidData[] calldata winningBids,
        PayeeData[] calldata payeeData
    ) external paymentsLock {
        // process protocol payments
        _disbursePayments(protocolShare, winningBids, payeeData);
        // TODO: who should pay gas cost of payments?
    } 

    function executeUserRefund(
        UserCall calldata userCall,
        bool callSuccess
    ) external refundLock {
        
        // TODO: searcher msg.value is being counted for gas rebate (double counted)

        // TODO: handle all the value transfer cases
        ValueTracker memory pendingValueTracker = _pendingValueTracker;

        // lazy way to avoid underflow/overflow
        // TODO: be better

        int256 startingBalance = int256(uint256(pendingValueTracker.starting));
        int256 endingBalance = int256(address(this).balance);
        int256 transferredIn = int256(uint256(pendingValueTracker.transferredIn));
        int256 transferredOut = int256(uint256(pendingValueTracker.transferredOut));
        int256 gasRebate = int256(uint256(pendingValueTracker.gasRebate));

        int256 valueReturn = (
            (
                endingBalance - startingBalance // total net
            ) + (
                gasRebate // add back in the gasRebate which was debited from searcher escrow
            ) - (
                transferredOut - transferredIn // subtract net outflows (IE add net inflows)
            )
        );

        emit UserTxResult(
            userCall.from,
            userCall.to,
            callSuccess,
            valueReturn > 0 ? uint256(valueReturn) : 0,
            uint256(pendingValueTracker.gasRebate)
        );

        // TODO: should revert on a negative valueReturn? should subtract from gasRefund?
        // thought: if we subtract from refund that allows users to play a salmonella-esque
        // game of gas chicken w/ naive searchers by gaming the storage refunds, since the 
        // refunds aren't accounted for until the end of the transaction and would only benefit 
        // the user. User could technically vampire attack naive searchers that way and profit 
        // from the value return, but informed searchers should be able to identify and block it.
        require(valueReturn > 0, "ERR-UP02 UnpaidValue");

        SafeTransferLib.safeTransferETH(
            userCall.from, 
            uint256(valueReturn + gasRebate)
        );

        delete _pendingValueTracker;
    }

    function _update(
        SearcherEscrow memory searcherEscrow,
        uint256 gasWaterMark,
        uint256 result,
        SearcherCall calldata searcherCall
    )  internal closeSearcherLock {

        uint256 gasRebate;
        uint256 txValue;

        // TODO: clean up code / make it readable
        if (result & _FULL_REFUND != 0) {
            gasRebate = (
                100 + SEARCHER_GAS_BUFFER
            ) * (
                // TODO: simplify/fix formula for calldata - verify. 
                (tx.gasprice * GWEI * (gasWaterMark-gasleft())) +
                (tx.gasprice * GWEI * (searcherCall.metaTx.data.length * 16))
            ) / 100;

            txValue = searcherCall.metaTx.value;
        
        // TODO: figure out what is fair for this(or if it just doesnt happen?)
        } else if (result & _EXTERNAL_REFUND != 0) {
            // TODO: simplify/fix formula for calldata - verify. 
            gasRebate = (
                (tx.gasprice * GWEI * (gasWaterMark-gasleft())) +
                (tx.gasprice * GWEI * (searcherCall.metaTx.data.length * 16))
            );

            txValue = searcherCall.metaTx.value;

        
        } else if (result & _CALLDATA_REFUND != 0) {
            gasRebate = (
                100 + SEARCHER_GAS_BUFFER
            ) * (
                // TODO: simplify/fix formula for calldata - verify. 
                (tx.gasprice * GWEI * (searcherCall.metaTx.data.length * 16))
            ) / 100;

            txValue = searcherCall.metaTx.value;
        
        } else if (result & _NO_REFUND != 0) {
            // pass
        
        } else {
            revert("ERR-SE72 UncoveredResult");
        }

        // handle overspending from txValue
        // TODO: not sure if necessary
        // TODO: if is necessary, fix via _pendingValueTracker
        if (gasRebate + txValue > searcherEscrow.total - searcherEscrow.escrowed) {
            uint256 escrowDelta = (gasRebate + txValue) - (searcherEscrow.total - searcherEscrow.escrowed);
            searcherEscrow.total -= uint128(searcherEscrow.total > escrowDelta ? escrowDelta : searcherEscrow.total);
            searcherEscrow.escrowed -= uint128(searcherEscrow.escrowed > escrowDelta ? escrowDelta : searcherEscrow.escrowed);
        }

        // make sure we don't underflow 
        gasRebate = gasRebate > searcherEscrow.total - txValue ? 
            searcherEscrow.total : 
            gasRebate ;

        _pendingValueTracker.gasRebate += uint128(gasRebate);
        searcherEscrow.total -= uint128(gasRebate); 

        // save the escrow data back into storage
        _escrowData[searcherCall.metaTx.from] = searcherEscrow;
    }

    function _verify(
        bytes32 targetHash,
        bytes32 userCallHash,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) internal openSearcherLock(targetHash, searcherCall.metaTx.to, searcherCall.metaTx.data)
        returns (uint256 result, uint256 gasLimit, SearcherEscrow memory searcherEscrow) 
    {
        // verify searcher's signature
        if (_verifySignature(searcherCall.metaTx, searcherCall.signature)) {
            // verify the searcher has correct usercalldata and the searcher escrow checks
            (result, gasLimit, searcherEscrow) = _verifySearcherCall(
                userCallHash, callSuccess, searcherCall
            );
            
        } else {
            (result, gasLimit) = (1 << uint256(SearcherOutcome.InvalidSignature), 0);
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

    function _verifySearcherCall(
        bytes32 userCallHash,
        bool callSuccess,
        SearcherCall calldata searcherCall
    ) internal returns (
            uint256 result, 
            uint256 gasLimit,
            SearcherEscrow memory searcherEscrow
    ) {

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

        searcherEscrow = _escrowData[searcherCall.metaTx.from];
        
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

        gasLimit = (
            100 + SEARCHER_GAS_BUFFER
        ) * (
            searcherCall.metaTx.gas < SEARCHER_GAS_LIMIT ? searcherCall.metaTx.gas : SEARCHER_GAS_LIMIT
        ) / (
            100
        ); 

        // see if searcher's escrow can afford tx gascost + tx value
        if (
            (
                (tx.gasprice * GWEI * gasLimit) +
                (searcherCall.metaTx.data.length * 16 * GWEI) +
                searcherCall.metaTx.value
            ) < (
                searcherEscrow.total - searcherEscrow.escrowed
            ) 
        ) {
            
            // charge searcher for calldata so that we can avoid vampire attacks from searcher onto user
            result |= 1 << uint256(SearcherOutcome.InsufficientEscrow);
        }
    }

    receive() external payable {
        if (gasleft() > 3_000) {
            if (
                msg.sender == _escrowKey.approvedCaller && 
                msg.sender != address(0)
            ) {
                _pendingValueTracker.transferredIn += uint128(msg.value);
            }
        }
    }

    fallback() external payable {
        revert(); // no untracked balance transfers plz. (not that this fully stops it)
    }

    // BITWISE STUFF
    function _searcherCallPreCheck(
        uint256 result, 
        uint256 gasWaterMark,
        uint256 txGasPrice,
        uint256 maxFeePerGas,
        bool callSuccess
    ) internal pure returns (uint256) {
        
        if (callSuccess) {
            result |= 1 << uint256(SearcherOutcome.NotWinner);
        } 
        
        if (gasWaterMark < VALIDATION_GAS_LIMIT + SEARCHER_GAS_LIMIT) {
            // Make sure to leave enough gas for protocol validation calls
            result |= 1 << uint256(SearcherOutcome.UserOutOfGas);
        } 
        
        if (txGasPrice > maxFeePerGas) {
            result |= 1 << uint256(SearcherOutcome.GasPriceOverCap);
        }
        
        return result;
    }
}