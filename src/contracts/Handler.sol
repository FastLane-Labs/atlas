//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { FastLaneDataTypes } from "./DataTypes.sol";
import { FastLaneErrorsEvents } from "./Emissions.sol";

import { FastLaneEscrow } from "./searcherEscrow.sol";
import { ThogLock } from "./ThogLock.sol";

interface IFastLaneEscrow {
    function verify(
        bytes32 userCallHash,
        SearcherCall calldata searcherCall
    ) external returns (uint256, uint256);

    struct SearcherEscrow {
        uint128 total;
        uint128 escrowed;
        uint64 availableOn; // block.number when funds are available.  
        uint64 lastAccessed;
        uint32 nonce; // EOA nonce.
    }

    struct SearcherCall {
        SearcherMetaTx metaTx;
        bytes signature;
        BidData[] bids;
    }

    struct SearcherMetaTx {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes32 userCallHash; // hash of user EOA and calldata, for verification of user's tx (if not matched, searcher wont be charged for gas)
        uint256 maxFeePerGas; // maxFeePerGas searcher is willing to pay.  This goes to validator, not protocol or user
        bytes32 bidsHash; // searcher's backend must keccak256() their BidData array and include that in the signed meta tx, which we then verify on chain. 
        bytes data;
    }

    struct BidData {
        address token;
        uint256 bidAmount;
    }
}

interface ISearcherContract {

    struct BidData {
        address token;
        uint256 bidAmount;
    }

    function metaFlashCall(
        address sender, 
        bytes calldata searcherCalldata, 
        BidData[] calldata bids
    ) external payable returns (bool, bytes memory);
}


contract FastLaneProtoHandler is FastLaneDataTypes, FastLaneErrorsEvents, ThogLock {

    bytes32 constant internal _SEARCHER_BID_UNPAID = keccak256(abi.encodePacked("SearcherBidUnpaid"));
    bytes32 constant internal _SEARCHER_CALL_REVERTED = keccak256(abi.encodePacked("SearcherCallReverted"));

    address immutable internal _factory;
    address immutable internal _escrow;

    uint256 immutable internal _protocolShare;

    constructor(
        uint16 protocolShare, 
        address escrow

    ) ThogLock(escrow, msg.sender) {
        _factory = msg.sender; // TODO: hardcode the factory?
        _escrow = escrow;

        _protocolShare = uint256(protocolShare);

        // meant to be a single-shot execution environment
        selfdestruct(payable(_factory));
    
    } 

    function protoCall( // haha get it?
        Lock memory mLock, // TODO: verify nested delegatecall cant access this
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable {

        mLock._lockCode ^= uint256(keccak256(abi.encodePacked(userCall.from)));

        // verify that the staging data provided by frontend was built around the 
        // actual user call.  
        bytes32 userCallHash = keccak256(abi.encodePacked(userCall.to, userCall.data));

        // NOTE: the stagingCall can be manipulated by an adversarial user.
        // this first check is meant as a gas-saving courtesy for frontend errors. 
        require(userCallHash == stagingCall.userCallHash, "ERR-01 UserCalldata");

        // declare some variables
        bool callSuccess; // reuse memory variable
        bytes memory stagingData; // capture any pre-execution state variables the protocol may need
        bytes memory returnData; // capture any pre-execution state variables the protocol may need

        // Stage the execution environment for the user, if necessary
        // NOTE: this is a trusted delegatecall... approve & trusted protocols only
        // NOTE: staging will almost certainly be auto-disabled for any upgradeable contracts
        if (stagingCall.stagingSelector != bytes4(0)) {
            (callSuccess, stagingData) = stagingCall.to.delegatecall(
                    bytes.concat(stagingCall.stagingSelector, userCall.data[4:])
            );
            require(callSuccess, "ERR-02 Staging");
        }

        // Do the user's call
        (callSuccess, returnData) = userCall.to.call(userCall.data);
        require(callSuccess, "ERR-03 UserCall");

        // init some vars for the searcher loop
        uint256 result;
        uint256 cumulativeGasRebate;
        uint256 gasWaterMark = gasleft();
        uint256 gasRebate; // might need to put the three gas uints into a struct
        uint256 gasLimit; 
        uint256 i; // init at 0
        callSuccess = false;

        for (; i < searcherCalls.length;) {

            (result, gasRebate, gasLimit) = FastLaneEscrow(_escrow).verify(
                userCallHash,
                callSuccess,
                searcherCalls[i]
            );

            if (callSuccess) {
                result |= 1 << uint256(SearcherOutcome.NotWinner);
            } 
            
            if (gasWaterMark < VALIDATION_GAS_LIMIT + SEARCHER_GAS_LIMIT) {
                // Make sure to leave enough gas for protocol validation calls
                result |= 1 << uint256(SearcherOutcome.UserOutOfGas);
            } 
            
            if (tx.gasprice > searcherCalls[i].metaTx.maxFeePerGas) {
                result |= 1 << uint256(SearcherOutcome.GasPriceOverCap);
            }

            // If there are no errors, attempt to execute
            // NOTE: the lowest bit is a tracker (PendingUpdate) and can be ignored
            if ((result >>1) == 0) {
                result |= (
                    1 << uint256(_searcherCallExecutor(gasLimit, searcherCalls[i])) |
                    1 << uint256(SearcherOutcome.ExecutionCompleted)
                );
            }

            if (result & 1 << uint256(SearcherOutcome.PendingUpdate) == 0) {
                gasRebate += FastLaneEscrow(_escrow).update(
                    gasWaterMark,
                    result,
                    searcherCalls[i]
                );
            }

            if (
                !(callSuccess) && 
                !(result & 1 << uint256(SearcherOutcome.ExecutionCompleted) == 0)
            ) { 
                if (result & 1 << uint256(SearcherOutcome.Success)  == 0) {
                    callSuccess = true;

                    // process protocol payments
                    _handlePayments(searcherCalls[i].bids, payeeData);
                }
            }

            mLock = _turnKeyUnsafe(mLock, searcherCalls[i]);

            cumulativeGasRebate += gasRebate;
            unchecked { ++i; }
            gasWaterMark = gasleft();
        }

        // handle gas rebate
        SafeTransferLib.safeTransferETH(
            userCall.from, 
            cumulativeGasRebate
        );

        // Run a post-searcher verification check with the data from the staging call
        if (stagingCall.verificationSelector != bytes4(0)) {
            // Unlike the staging call, this isn't delegatecall
            (callSuccess,) = stagingCall.to.call(
                abi.encodeWithSelector(stagingCall.verificationSelector, stagingData)
            );
            require(callSuccess, "ERR-07 Verification");
        }

        _unlock(mLock);
    }

    function _handlePayments(
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) internal {
        // NOTE: the relay/frontend will verify that the bid 
        //and payments arrays are aligned
        // NOTE: pour one out for the eth mainnet homies
        // that'll need to keep their payee array short :(
        
        // declare some vars to make this trainwreck less unreadable
        PaymentData memory pmtData;
        ERC20 token;
        uint256 payment;
        uint256 bidAmount;
        bool callSuccess;

        uint256 i;
        uint256 k;        

        for (; i < bids.length;) {
            token = ERC20(bids[i].token);
            bidAmount = bids[i].bidAmount;

            for (; k < payeeData[i].payments.length;) {

                pmtData = payeeData[i].payments[k];
                
                payment = bidAmount * pmtData.payeePercent / (100 + _protocolShare);

                if (pmtData.pmtSelector != bytes4(0)) {
                    // TODO: handle native token / ETH
                    SafeTransferLib.safeTransfer(token, pmtData.payee, payment);
                
                } else {
                    // TODO: formalize the args for this (or use bytes set by frontend?)
                    // (it's (address, uint256) atm)
                    // TODO: even tho we control the frontend which populates the payee
                    // info, this is dangerous af and prob shouldn't be done this way
                    (callSuccess,) = pmtData.payee.delegatecall(
                        abi.encodeWithSelector(
                            pmtData.pmtSelector, 
                            bids[i].token,
                            payment    
                        )
                    );
                    require(callSuccess, "ERR-05 ProtoPmt");
                }
                
                // Protocol Fee is remainder
                // NOTE: this assumption does not work for native token / ETH
                SafeTransferLib.safeTransfer(token, _factory, token.balanceOf(address(this)));

                unchecked{ ++k;}
            }

            unchecked{ ++i;}
        }
    }

    function _searcherCallExecutor(
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) internal returns (SearcherOutcome) {
        
        try this.searcherMetaWrapper(gasLimit, searcherCall) {
            return SearcherOutcome.Success;
        
        } catch Error(string memory err)  {
            if (keccak256(abi.encodePacked(err)) == _SEARCHER_BID_UNPAID) {
                // TODO: implement cheaper way to do this
                return SearcherOutcome.BidNotPaid;
            } else {
                return SearcherOutcome.CallReverted;
            }
        
        } catch {
            return SearcherOutcome.CallReverted;
        }
    }

    function searcherMetaWrapper(
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external {

        // no idea if this require works for a self-external try/catch lul
        require(msg.sender == address(this), "ERR-04 Self-Call-Only");

        // TODO: need to handle native eth
        // TODO: this contract won't hold balances other than eth, so this might be unnecessary
        uint256[] memory tokenBalances = new uint[](searcherCall.bids.length);
        uint256 i;

        for (; i < searcherCall.bids.length;) {
            tokenBalances[i] = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
            unchecked {++i;}
        }

        (bool success,) = ISearcherContract(searcherCall.metaTx.to).metaFlashCall{
            gas: gasLimit, 
            value: searcherCall.metaTx.value
        }(
            searcherCall.metaTx.from,
            searcherCall.metaTx.data,
            searcherCall.bids
        );

        require(success, "SearcherCallReverted");

        i = 0;
        for (; i < searcherCall.bids.length;) {
            
            require(
                ERC20(searcherCall.bids[i].token).balanceOf(address(this)) >= tokenBalances[i] + searcherCall.bids[i].bidAmount,
                "SearcherBidUnpaid"
            );
            
            unchecked {++i;}
        }
    }
}
