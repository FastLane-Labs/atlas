//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { Escrow } from "./searcherEscrow.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

interface ISearcherContract {
    function metaFlashCall(
        address sender, 
        bytes calldata searcherCalldata, 
        BidData[] calldata bids
    ) external payable returns (bool, bytes memory);
}

/// @notice contract call set by front end to prepare state for user's call (IE token transfers to address(this))
/// @param to address to call
/// @param stagingSelector func selector to call
/// @dev This is set by the front end!
/// @dev The stagingSelector's argument types must match the user's call's argument types to properly stage the meta tx.
struct StagingCall { 
    address to;
    bytes4 stagingSelector;
    bytes4 verificationSelector;
}

struct UserCall {
    address to;
    bytes data;
}

struct SearcherCall {
    uint256 maxFeePerGas; // maxFeePerGas searcher is willing to pay.  This goes to validator, not protocol or user
    SearcherMetaTx metaTx;
    bytes signature;
    BidData[] bids;
}

struct BidData {
    address token;
    uint256 bidAmount;
}

struct SearcherMetaTx {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    bytes data;
}

/// @notice protocol payee Data Struct
/// @param token token address (ERC20) being paid
struct PayeeData {
    address token;
    PaymentData[] payments;
}

/// @param payee address to pay
/// @param payeePercent percentage of bid to pay to payee (base 100)
/// @dev must sum to 100
struct PaymentData {
    address payee;
    uint256 payeePercent;
    bytes4 pmtSelector; // func selector (on payee contract) to call for custom pmt function. leave blank if payee receives funds via ERC20 transfer
    // TODO: formalize / customize args for pmtSelector?
}

enum SearcherOutcome {
    NotExecuted, // a higher bidding searcher was successful
    OutOfGas,
    GasPriceOverCap,
    InsufficientEscrow,
    AlreadyExecuted,
    InvalidNonce,
    InvalidSignature,
    InvalidFormat,
    CallReverted,
    BidNotPaid,
    Success
}

contract FastLaneProtoHandler is ReentrancyGuard, EIP712 {
    using Escrow for Escrow.SearcherEscrow;
    using ECDSA for bytes32;

    bytes32 internal constant _TYPE_HASH =
        keccak256("SearcherMetaTx(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    uint256 constant public SEARCHER_GAS_LIMIT = 1_000_000;
    uint256 constant public VALIDATION_GAS_LIMIT = 500_000;
    uint256 constant public GWEI = 1_000_000_000;

    bytes32 constant internal _SEARCHER_BID_UNPAID = keccak256(abi.encodePacked("SearcherBidUnpaid"));
    bytes32 constant internal _SEARCHER_CALL_REVERTED = keccak256(abi.encodePacked("SearcherCallReverted"));

    uint256 immutable public chainId;
    uint256 immutable public protocolShare;
    uint32 immutable public escrowDuration;
    address immutable public fastLanePayee;

    uint256 public fastLanePayable; // init at 0

    // EOA Address => searcher escrow data
    mapping(address => Escrow.SearcherEscrow) internal _escrowData;

    // track searcher tx hashes to avoid replays... imperfect solution tho
    mapping(bytes32 => bool) internal _hashes;

    constructor(
            address _fastlanePayee, 
            uint256 _protocolShare,
            uint32 _escrowDuration
    ) EIP712("ProtoHandler", "0.0.1") {

        fastLanePayee = _fastlanePayee;
        protocolShare = _protocolShare;
        chainId = block.chainid;
        escrowDuration = _escrowDuration;
    }

    function protoCall( // haha get it?
        StagingCall calldata stagingCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable nonReentrant() {

        // shameless tbh
        require(tx.origin == msg.sender, "ERR-00 Sender");

        // declare some variables
        bool callSuccess; // reuse memory variable
        bytes memory stagingData; // capture any pre-execution state variables the protocol may need
        bytes memory returnData; // capture any pre-execution state variables the protocol may need


        // Stage the execution environment for the user, if necessary
        if (stagingCall.stagingSelector != bytes4(0)) {
            (callSuccess, stagingData) = stagingCall.to.delegatecall(
                    bytes.concat(stagingCall.stagingSelector, userCall.data[4:])
            );
            require(callSuccess, "ERR-01 Staging");
        }

        // Do the user's call
        (callSuccess, returnData) = userCall.to.call(userCall.data);
        require(callSuccess, "ERR-02 UserCall");

        // init some vars for the searcher loop
        SearcherOutcome result;
        uint256 gasWaterMark = gasleft();
        uint256 gasRebate;
        uint256 x;
        uint256 i; // init at 0
        callSuccess = false;
        for (; i < searcherCalls.length;) {

            if (callSuccess) {
                _optimisticMark(searcherCalls[i]);

            } else if (gasWaterMark < VALIDATION_GAS_LIMIT + SEARCHER_GAS_LIMIT) {
                // Make sure to leave enough gas for protocol validation calls
                _optimisticMark(searcherCalls[i]);
                result = SearcherOutcome.OutOfGas;
            
            } else if (tx.gasprice > searcherCalls[i].maxFeePerGas) {
                _optimisticMark(searcherCalls[i]);
                result = SearcherOutcome.GasPriceOverCap;

            } else {
                result = _searcherCallExecutor(searcherCalls[i]);
            }

            // failures 0,1,2 should be caught at relay / frontend 
            // but these checks will make searchers more comfy
            if (!callSuccess && uint8(result) > 2) { 
                x = (tx.gasprice * GWEI * (gasWaterMark - gasleft())) + searcherCalls[i].metaTx.value;
                
                _escrowData[searcherCalls[i].metaTx.from].total -= uint128(x); // TODO: add in some underflow handling
                gasRebate += x;
            
                if (result == SearcherOutcome.Success) {
                    callSuccess = true;
                    
                    // handle gas rebate
                    SafeTransferLib.safeTransferETH(
                            msg.sender, 
                            gasRebate
                    );

                    // process protocol payments
                    _handlePayments(searcherCalls[i].bids, payeeData);
                }
            }
            unchecked { ++i; }
            gasWaterMark = gasleft();
        }

        // Run a post-searcher verification check with the data from the staging call
        if (stagingCall.verificationSelector != bytes4(0)) {
            // Unlike the staging call, this isn't delegatecall
            (callSuccess,) = stagingCall.to.call(
                abi.encodeWithSelector(stagingCall.verificationSelector, stagingData)
            );
            require(callSuccess, "ERR-07 Verification");
        }
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
                
                payment = bidAmount * pmtData.payeePercent / (100 + protocolShare);

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
                SafeTransferLib.safeTransfer(token, fastLanePayee, token.balanceOf(address(this)));

                unchecked{ ++k;}
            }

            unchecked{ ++i;}
        }
    }

    function _optimisticMark(SearcherCall calldata searcherCall) internal {
        _hashes[keccak256(searcherCall.signature)] = true;

        // optimistically increment nonce w/o recover once a searcher succeeds
        // this'll save gas, and itll be verified at the relay level to prevent spoofing
        if (searcherCall.metaTx.nonce == uint256(_escrowData[searcherCall.metaTx.from].nonce)) {
            unchecked {
                ++_escrowData[searcherCall.metaTx.from].nonce;
            }
        }
    }

    function _searcherCallExecutor(
        SearcherCall calldata searcherCall
    ) internal returns (SearcherOutcome) {
        
        Escrow.SearcherEscrow memory searcherEscrow = _escrowData[searcherCall.metaTx.from];

        uint256 gasLimit = searcherCall.metaTx.gas < SEARCHER_GAS_LIMIT ? searcherCall.metaTx.gas : SEARCHER_GAS_LIMIT;

        // see if searcher's escrow can afford tx gascost + tx value
        if ((tx.gasprice * GWEI * gasLimit) + searcherCall.metaTx.value < searcherEscrow.available()) {
            return SearcherOutcome.InsufficientEscrow;
        }

        bytes32 searcherHash = keccak256(searcherCall.signature);
        
        if (_hashes[searcherHash]) {
            // TODO: emit something to flag the fastlane relay
            // this error should be 100% preventable at the relay level 
            return SearcherOutcome.AlreadyExecuted;
        }

        _hashes[searcherHash] = true;

        if (searcherCall.metaTx.nonce != uint256(searcherEscrow.nonce)) {
            return SearcherOutcome.InvalidNonce;
        }

        // TODO: make better verify func. this is just a placeholder for meta txs
        if (!verify(searcherCall.metaTx, searcherCall.signature)) {
            return SearcherOutcome.InvalidSignature;
        }

        unchecked {
            ++_escrowData[searcherCall.metaTx.from].nonce;
        }

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

    // TODO: make a more thorough version of this
    function verify(
            SearcherMetaTx calldata req, 
            bytes calldata signature
    ) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(_TYPE_HASH, req.from, req.to, req.value, req.gas, req.nonce, keccak256(req.data)))
        ).recover(signature);
        return signer == req.from;
    }

}
