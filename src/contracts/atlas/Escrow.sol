//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {SafetyLocks} from "./SafetyLocks.sol";
import {SearcherWrapper} from "./SearcherWrapper.sol";
import {ProtocolVerifier} from "./ProtocolVerification.sol";

import "../types/CallTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

import {EscrowBits} from "../libraries/EscrowBits.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

// import "forge-std/Test.sol";

contract Escrow is ProtocolVerifier, SafetyLocks, SearcherWrapper {
    using ECDSA for bytes32;
    using EscrowBits for uint256;
    using CallBits for uint16;    
    using SafetyBits for EscrowKey;

    uint256 constant public BUNDLER_PREMIUM = 110; // the amount over cost that bundlers get paid
    uint256 constant public BUNDLER_BASE = 100;

    uint32 public immutable escrowDuration;

    // NOTE: these storage vars / maps should only be accessible by *signed* searcher transactions
    // and only once per searcher per block (to avoid user-searcher collaborative exploits)
    // EOA Address => searcher escrow data
    mapping(address => SearcherEscrow) internal _escrowData;
    mapping(address => SearcherWithdrawal) internal _withdrawalData;

    GasDonation[] internal _donations;

    constructor(
        uint32 escrowDurationFromFactory //,
            //address _atlas
    ) SafetyLocks() {
        escrowDuration = escrowDurationFromFactory;
    }

    ///////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS FOR SEARCHER INTERACTION ///
    ///////////////////////////////////////////////////
    function deposit(address searcherMetaTxSigner) external payable returns (uint256 newBalance) {
        // NOTE: The escrow accounting system cannot currently handle deposits made mid-transaction.
        require(activeEnvironment == address(0), "ERR-E001 AlreadyInitialized");

        _escrowData[searcherMetaTxSigner].total += uint128(msg.value);
        newBalance = uint256(_escrowData[searcherMetaTxSigner].total);
    }

    function nextSearcherNonce(address searcherMetaTxSigner) external view returns (uint256 nextNonce) {
        nextNonce = uint256(_escrowData[searcherMetaTxSigner].nonce) + 1;
    }

    function searcherEscrowBalance(address searcherMetaTxSigner) external view returns (uint256 balance) {
        balance = uint256(_escrowData[searcherMetaTxSigner].total);
    }

    function searcherLastActiveBlock(address searcherMetaTxSigner) external view returns (uint256 lastBlock) {
        lastBlock = uint256(_escrowData[searcherMetaTxSigner].lastAccessed);
    }

    ///////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS FOR BUNDLER INTERACTION  ///
    ///////////////////////////////////////////////////

    // TODO: The balance checks on escrow that verify that the searcher
    // paid back any msg.value that they borrowed are currently not set up 
    // to handle gas donations to the bundler from the searcher.
    // THIS IS EXPLOITABLE - DO NOT USE THIS CONTRACT IN PRODUCTION
    // This attack vector will be addressed explicitly once the gas 
    // reimbursement mechanism is finalized.

    function donateToBundler(address surplusRecipient) external payable {
        // NOTE: All donations in excess of 10% greater than cost are forwarded
        // to the surplusReceiver. 

        require(msg.sender != address(0) && msg.sender == activeEnvironment, "ERR-E079 DonateRequiresLock");
        if (msg.value == 0) {
            return;
        }

        uint32 gasRebate = uint32(msg.value / tx.gasprice);

        uint256 donationCount = _donations.length;

        if (donationCount == 0) {
            _donations.push(GasDonation({
                recipient: surplusRecipient,
                net: gasRebate,
                cumulative: gasRebate
            }));
            return;
        }

        GasDonation memory donation = _donations[donationCount-1];

        // If the recipient is the same as the last one, just 
        // increment the values and reuse the slot 
        if (donation.recipient == surplusRecipient) {
            donation.net += gasRebate;
            donation.cumulative += gasRebate;
            _donations[donationCount-1] = donation;
            return;
        }

        // If it's a new recipient, update and push to the storage array
        donation.recipient = surplusRecipient;
        donation.net = gasRebate;
        donation.cumulative += gasRebate;
        _donations.push(donation);
    }

    function cumulativeDonations() external view returns (uint256) {
        uint256 donationCount = _donations.length;

        if (donationCount == 0) {
            return 0;
        }

        uint32 gasRebate = _donations[donationCount-1].cumulative;
        return uint256(gasRebate) * tx.gasprice;

    }

    ///////////////////////////////////////////////////
    ///             INTERNAL FUNCTIONS              ///
    ///////////////////////////////////////////////////
    function _executeStagingCall(
        UserMetaTx calldata userMetaTx,
        address environment,
        bytes32 lockBytes
    ) 
        internal 
        returns (bytes memory stagingData) 
    {
        bool success;
        stagingData = abi.encodeWithSelector(IExecutionEnvironment.stagingWrapper.selector, userMetaTx);
        stagingData = abi.encodePacked(stagingData, lockBytes);
        (success, stagingData) = environment.call{value: msg.value}(stagingData);
        require(success, "ERR-E001 StagingFail");
        stagingData = abi.decode(stagingData, (bytes));
    }

    function _executeUserCall(
        UserMetaTx calldata userMetaTx, 
        address environment,
        bytes32 lockBytes
    )
        internal
        returns (bytes memory userData)
    {
        bool success;
        userData = abi.encodeWithSelector(IExecutionEnvironment.userWrapper.selector, userMetaTx);
        userData = abi.encodePacked(userData, lockBytes);
        // TODO: Handle msg.value quirks
        (success, userData) = environment.call(userData);
        require(success, "ERR-E002 UserFail");
        userData = abi.decode(userData, (bytes));
    }

    function _executeSearcherCall(
        SearcherCall calldata searcherCall,
        bytes memory returnData,
        address environment,
        EscrowKey memory key
    ) internal returns (bool, EscrowKey memory) {

        // Set the gas baseline
        uint256 gasWaterMark = gasleft();

        // Verify the transaction.
        (uint256 result, uint256 gasLimit, SearcherEscrow memory searcherEscrow) =
            _verify(searcherCall, gasWaterMark, false);

        SearcherOutcome outcome;
        uint256 escrowSurplus;
        bool auctionWon;

        // If there are no errors, attempt to execute
        if (result.canExecute()) {
            // Open the searcher lock
            key = key.holdSearcherLock(searcherCall.metaTx.to);
           
            // Execute the searcher call
            (outcome, escrowSurplus) = _searcherCallWrapper(gasLimit, environment, searcherCall, returnData, key.pack());

            unchecked {
                searcherEscrow.total += uint128(escrowSurplus);
            }

            result |= 1 << uint256(outcome);

            if (result.executedWithError()) {
                result |= 1 << uint256(SearcherOutcome.ExecutionCompleted);
            } else if (result.executionSuccessful()) {
                // first successful searcher call that paid what it bid
                auctionWon = true; // cannot be reached if bool is already true
                result |= 1 << uint256(SearcherOutcome.ExecutionCompleted);
                key = key.turnSearcherLockPayments(environment);
            }

            // Update the searcher's escrow balances and the accumulated refund
            if (result.updateEscrow()) {
                key.gasRefund += uint32(_update(searcherCall.metaTx, searcherEscrow, gasWaterMark, result));
            }

            // emit event
            emit SearcherTxResult(
                searcherCall.metaTx.to,
                searcherCall.metaTx.from,
                true,
                outcome == SearcherOutcome.Success,
                searcherEscrow.nonce,
                result
            );

        } else {
            // emit event
            emit SearcherTxResult(
                searcherCall.metaTx.to,
                searcherCall.metaTx.from,
                false,
                false,
                searcherEscrow.nonce,
                result
            );
        }

        return (auctionWon, key);
    }

    // TODO: who should pay gas cost of MEV Payments?
    // TODO: Should payment failure trigger subsequent searcher calls?
    // (Note that balances are held in the execution environment, meaning
    // that payment failure is typically a result of a flaw in the
    // ProtocolControl contract)
    function _executePayments(
        ProtocolCall calldata protocolCall,
        BidData[] calldata winningBids,
        bytes memory returnData,
        address environment,
        bytes32 lockBytes
    ) internal {
        // process protocol payments
        bool success;
        bytes memory data = abi.encodeWithSelector(IExecutionEnvironment.allocateRewards.selector, winningBids, returnData);
        data = abi.encodePacked(data, lockBytes);
        (success, ) = environment.call(data);
        if (!success) {
            emit MEVPaymentFailure(protocolCall.to, protocolCall.callConfig, winningBids);
        }
    }

    function _executeVerificationCall(
        bytes memory returnData,
        address environment,
        bytes32 lockBytes
    ) internal {
        bool success;
        bytes memory verificationData = abi.encodeWithSelector(IExecutionEnvironment.verificationWrapper.selector, returnData);
        verificationData = abi.encodePacked(verificationData, lockBytes);
        (success,) = environment.call{value: msg.value}(verificationData);
        require(success, "ERR-E005 VerificationFail");
    }

    function _executeGasRefund(uint256 gasMarker, uint256 accruedGasRebate, address user) internal {
        // TODO: Consider tipping validator / builder here to incentivize a non-adversarial environment?
        
        GasDonation[] memory donations = _donations;
        
        delete _donations;

        uint256 gasFeesSpent = ((gasMarker + 41_000 - gasleft()) * tx.gasprice * BUNDLER_PREMIUM) / BUNDLER_BASE;
        uint256 gasFeesCredit = accruedGasRebate * tx.gasprice;
        uint256 returnFactor = 0; // Out of 100

        // CASE: gasFeesCredit fully covers what's been spent.
        // NOTE: Should be impossible to reach
        if (gasFeesCredit > gasFeesSpent) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesSpent);
            SafeTransferLib.safeTransferETH(user, gasFeesCredit - gasFeesSpent);
            
            returnFactor = 100;

        // CASE: There are no donations, so just refund the searcher credits
        } else if (donations.length == 0) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesCredit);
            return;

        // CASE: There are no donations, so just refund the searcher credits and return
        } else if (donations[donations.length-1].cumulative == 0) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesCredit);
            return;

        // CASE: The donations exceed the liability
        } else if (donations[donations.length-1].cumulative > gasFeesSpent - gasFeesCredit) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesSpent);

            uint256 totalDonations = donations[donations.length-1].cumulative;
            uint256 excessDonations = totalDonations - (gasFeesSpent - gasFeesCredit);

            returnFactor = (100 * excessDonations) / (totalDonations + 1);

        // CASE: The bundler receives all of the donations
        } else {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesCredit);
            return;
        }

        // Return any surplus donations
        // TODO: de-dust it
        if (returnFactor > 0) {
            uint256 i;
            uint256 surplus;
            address recipient;

            for (;i<donations.length;) {
                
                surplus = (donations[i].net * returnFactor) / 100;
                recipient = donations[i].recipient == address(0) ? user : donations[i].recipient;

                SafeTransferLib.safeTransferETH(recipient, surplus);

                unchecked{++i;}
            }
        }
    }

    function _update(
        SearcherMetaTx calldata metaTx,
        SearcherEscrow memory searcherEscrow,
        uint256 gasWaterMark,
        uint256 result
    ) internal returns (uint256 gasRebate) {
        unchecked {
            uint256 gasUsed = gasWaterMark - gasleft();

            if (result & EscrowBits._FULL_REFUND != 0) {
                gasRebate = gasUsed + (metaTx.data.length * CALLDATA_LENGTH_PREMIUM);
            } else if (result & EscrowBits._CALLDATA_REFUND != 0) {
                gasRebate = (metaTx.data.length * CALLDATA_LENGTH_PREMIUM);
            } else if (result & EscrowBits._NO_USER_REFUND != 0) {
                // pass
            } else {
                revert("ERR-SE72 UncoveredResult");
            }

            if (gasRebate != 0) {
                // Calculate what the searcher owes
                gasRebate *= tx.gasprice;

                gasRebate = gasRebate > searcherEscrow.total ? searcherEscrow.total : gasRebate;

                searcherEscrow.total -= uint128(gasRebate);

                // NOTE: This will cause an error if you are simulating with a gasPrice of 0
                gasRebate /= tx.gasprice;

                // save the escrow data back into storage
                _escrowData[metaTx.from] = searcherEscrow;
            
            // Check if need to save escrowData due to nonce update but not gasRebate
            } else if (result & EscrowBits._NO_NONCE_UPDATE == 0) {
                _escrowData[metaTx.from].nonce = searcherEscrow.nonce;
            }
        }
    }

    function _verify(SearcherCall calldata searcherCall, uint256 gasWaterMark, bool auctionAlreadyComplete)
        internal
        view
        returns (uint256 result, uint256 gasLimit, SearcherEscrow memory searcherEscrow)
    {
        // verify searcher's signature
        if (_verifySignature(searcherCall.metaTx, searcherCall.signature)) {
            // verify the searcher has correct usercalldata and the searcher escrow checks
            (result, gasLimit, searcherEscrow) = _verifySearcherCall(searcherCall);
        } else {
            (result, gasLimit) = (1 << uint256(SearcherOutcome.InvalidSignature), 0);
            // searcherEscrow returns null
        }

        result = _searcherCallPreCheck(
            result, gasWaterMark, tx.gasprice, searcherCall.metaTx.maxFeePerGas, auctionAlreadyComplete
        );
    }

    function _getSearcherHash(SearcherMetaTx calldata metaTx) internal pure returns (bytes32 searcherHash) {
        return keccak256(
            abi.encode(
                SEARCHER_TYPE_HASH,
                metaTx.from,
                metaTx.to,
                metaTx.value,
                metaTx.gas,
                metaTx.nonce,
                metaTx.maxFeePerGas,
                metaTx.userCallHash,
                metaTx.controlCodeHash,
                metaTx.bidsHash,
                keccak256(metaTx.data)
            )
        );
    }

    function getSearcherPayload(SearcherMetaTx calldata metaTx) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getSearcherHash(metaTx));
    }

    function _verifySignature(SearcherMetaTx calldata metaTx, bytes calldata signature) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getSearcherHash(metaTx)).recover(signature);
        return signer == metaTx.from;
    }

    function _verifyBids(bytes32 bidsHash, BidData[] calldata bids) internal pure returns (bool validBid) {
        // NOTE: this should only occur after the searcher's signature on the bidsHash is verified
        validBid = keccak256(abi.encode(bids)) == bidsHash;
    }

    function _verifySearcherCall(SearcherCall calldata searcherCall)
        internal
        view
        returns (uint256 result, uint256 gasLimit, SearcherEscrow memory searcherEscrow)
    {
        searcherEscrow = _escrowData[searcherCall.metaTx.from];

        unchecked {

            if (searcherCall.metaTx.nonce <= uint256(searcherEscrow.nonce)) {
                result |= 1 << uint256(SearcherOutcome.InvalidNonceUnder);
            } else if (searcherCall.metaTx.nonce > uint256(searcherEscrow.nonce) + 1) {
                result |= 1 << uint256(SearcherOutcome.InvalidNonceOver);

                // TODO: reconsider the jump up for gapped nonces? Intent is to mitigate dmg
                // potential inflicted by a hostile searcher/builder.
                searcherEscrow.nonce = uint32(searcherCall.metaTx.nonce);
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

            gasLimit = (100)
                * (
                    searcherCall.metaTx.gas < EscrowBits.SEARCHER_GAS_LIMIT
                        ? searcherCall.metaTx.gas
                        : EscrowBits.SEARCHER_GAS_LIMIT
                ) / (100 + EscrowBits.SEARCHER_GAS_BUFFER) + EscrowBits.FASTLANE_GAS_BUFFER;

            uint256 gasCost = (tx.gasprice * gasLimit) + (searcherCall.metaTx.data.length * CALLDATA_LENGTH_PREMIUM * tx.gasprice);

            // see if searcher's escrow can afford tx gascost
            if (gasCost > searcherEscrow.total - _withdrawalData[searcherCall.metaTx.from].escrowed) {
                // charge searcher for calldata so that we can avoid vampire attacks from searcher onto user
                result |= 1 << uint256(SearcherOutcome.InsufficientEscrow);
            }

            // Verify that we can lend the searcher their tx value
            if (searcherCall.metaTx.value > address(this).balance - (gasLimit * tx.gasprice)) {
                result |= 1 << uint256(SearcherOutcome.CallValueTooHigh);
            }

            // subtract out the gas buffer since the searcher's metaTx won't use it
            gasLimit -= EscrowBits.FASTLANE_GAS_BUFFER;
        }
    }

    receive() external payable {}

    fallback() external payable {
        revert(); // no untracked balance transfers plz. (not that this fully stops it)
    }

    // BITWISE STUFF
    function _searcherCallPreCheck(
        uint256 result,
        uint256 gasWaterMark,
        uint256 txGasPrice,
        uint256 maxFeePerGas,
        bool auctionAlreadyComplete
    ) internal pure returns (uint256) {
        if (auctionAlreadyComplete) {
            result |= 1 << uint256(SearcherOutcome.LostAuction);
        }

        if (gasWaterMark < EscrowBits.VALIDATION_GAS_LIMIT + EscrowBits.SEARCHER_GAS_LIMIT) {
            // Make sure to leave enough gas for protocol validation calls
            result |= 1 << uint256(SearcherOutcome.UserOutOfGas);
        }

        if (txGasPrice > maxFeePerGas) {
            result |= 1 << uint256(SearcherOutcome.GasPriceOverCap);
        }

        return result;
    }
}
