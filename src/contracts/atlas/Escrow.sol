//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {SafetyLocks} from "./SafetyLocks.sol";
import {DAppVerification} from "./DAppVerification.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import {DAppConfig} from "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";
import {FastLaneErrorsEvents} from "../types/Emissions.sol";

import {EscrowBits} from "../libraries/EscrowBits.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Escrow is DAppVerification, SafetyLocks, FastLaneErrorsEvents {
    using ECDSA for bytes32;
    using EscrowBits for uint256;
    using CallBits for uint32;    
    using SafetyBits for EscrowKey;

    uint256 constant public BUNDLER_PREMIUM = 110; // the amount over cost that bundlers get paid
    uint256 constant public BUNDLER_BASE = 100;

    uint32 public immutable escrowDuration;

    // NOTE: these storage vars / maps should only be accessible by *signed* solver transactions
    // and only once per solver per block (to avoid user-solver collaborative exploits)
    // EOA Address => solver escrow data
    mapping(address => SolverEscrow) internal _escrowData;
    mapping(address => SolverWithdrawal) internal _withdrawalData;

    GasDonation[] internal _donations;
    AccountingData internal _accData;

    constructor(uint32 escrowDurationFromFactory, address _simulator) SafetyLocks(_simulator) {
        escrowDuration = escrowDurationFromFactory;
    }

    ///////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS FOR SOLVER INTERACTION ///
    ///////////////////////////////////////////////////
    function deposit(address solverSigner) onlyWhenUnlocked external payable returns (uint256 newBalance) {
        // NOTE: The escrow accounting system cannot currently handle deposits made mid-transaction.

        _escrowData[solverSigner].total += uint128(msg.value);
        newBalance = uint256(_escrowData[solverSigner].total);
    }

    function nextSolverNonce(address solverSigner) external view returns (uint256 nextNonce) {
        nextNonce = uint256(_escrowData[solverSigner].nonce) + 1;
    }

    function solverEscrowBalance(address solverSigner) external view returns (uint256 balance) {
        balance = uint256(_escrowData[solverSigner].total);
    }

    function solverLastActiveBlock(address solverSigner) external view returns (uint256 lastBlock) {
        lastBlock = uint256(_escrowData[solverSigner].lastAccessed);
    }

    ///////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS FOR BUNDLER INTERACTION  ///
    ///////////////////////////////////////////////////

    function donateToBundler(address surplusRecipient) external payable {
        // NOTE: All donations in excess of 10% greater than cost are forwarded
        // to the surplusReceiver. 
        require(msg.sender == activeEnvironment, "ERR-E079 DonateRequiresLock");

        // DDoS attacks prevented by only allowing 1 donation per phase in Exec Env
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
        donation.cumulative = gasRebate;
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
    function _executePreOpsCall(
        UserCall calldata uCall,
        address environment,
        bytes32 lockBytes
    ) 
        internal 
        returns (bool success, bytes memory preOpsData) 
    {
        preOpsData = abi.encodeWithSelector(IExecutionEnvironment.preOpsWrapper.selector, uCall);
        preOpsData = abi.encodePacked(preOpsData, lockBytes);
        (success, preOpsData) = environment.call{value: msg.value}(preOpsData);
        if (success) {
            preOpsData = abi.decode(preOpsData, (bytes));
        }
    }

    function _executeUserOperation(
        UserCall calldata uCall, 
        address environment,
        bytes32 lockBytes
    )
        internal
        returns (bool success, bytes memory userData)
    {
        userData = abi.encodeWithSelector(IExecutionEnvironment.userWrapper.selector, uCall);
        userData = abi.encodePacked(userData, lockBytes);
        // TODO: Handle msg.value quirks
        (success, userData) = environment.call(userData);
        // require(success, "ERR-E002 UserFail");
        if (success) {
            userData = abi.decode(userData, (bytes));
        }
    }

    function _executeSolverOperation(
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        address environment,
        EscrowKey memory key
    ) internal returns (bool auctionWon, EscrowKey memory) {

        // Set the gas baseline
        uint256 gasWaterMark = gasleft();

        // Verify the transaction.
        (uint256 result, uint256 gasLimit, SolverEscrow memory solverEscrow) =
            _verify(solverOp, gasWaterMark, false);

        SolverOutcome outcome;
        uint256 escrowSurplus;

        // If there are no errors, attempt to execute
        if (result.canExecute()) {
            // Open the solver lock
            key = key.holdSolverLock(solverOp.call.to);

            // Execute the solver call
            (outcome, escrowSurplus) = _solverOpWrapper(gasLimit, environment, solverOp, dAppReturnData, key.pack());

            unchecked {
                solverEscrow.total += uint128(escrowSurplus);
            }

            result |= 1 << uint256(outcome);

            if (result.executedWithError()) {
                result |= 1 << uint256(SolverOutcome.ExecutionCompleted);
            } else if (result.executionSuccessful()) {
                // first successful solver call that paid what it bid
                auctionWon = true; // cannot be reached if bool is already true
                result |= 1 << uint256(SolverOutcome.ExecutionCompleted);
                key = key.turnSolverLockPayments(environment);
            }

            // Update the solver's escrow balances and the accumulated refund
            if (result.updateEscrow()) {
                key.gasRefund += uint32(_update(solverOp.call, solverEscrow, gasWaterMark, result));
            }

            // emit event
            emit SolverTxResult(
                solverOp.call.to,
                solverOp.call.from,
                true,
                outcome == SolverOutcome.Success,
                solverEscrow.nonce,
                result
            );

        } else {
            // emit event
            emit SolverTxResult(
                solverOp.call.to,
                solverOp.call.from,
                false,
                false,
                solverEscrow.nonce,
                result
            );
        }

        return (auctionWon, key);
    }

    // TODO: who should pay gas cost of MEV Payments?
    // TODO: Should payment failure trigger subsequent solver calls?
    // (Note that balances are held in the execution environment, meaning
    // that payment failure is typically a result of a flaw in the
    // DAppControl contract)
    function _allocateValue(
        DAppConfig calldata dConfig,
        BidData[] calldata winningBids,
        bytes memory returnData,
        address environment,
        bytes32 lockBytes
    ) internal returns (bool success) {
        // process dApp payments
        bytes memory data = abi.encodeWithSelector(IExecutionEnvironment.allocateValue.selector, winningBids, returnData);
        data = abi.encodePacked(data, lockBytes);
        (success, ) = environment.call(data);
        if (!success) {
            emit MEVPaymentFailure(dConfig.to, dConfig.callConfig, winningBids);
        }
    }

    function _executePostOpsCall(
        bytes memory returnData,
        address environment,
        bytes32 lockBytes
    ) internal returns (bool success) {
        bytes memory postOpsData = abi.encodeWithSelector(IExecutionEnvironment.postOpsWrapper.selector, returnData);
        postOpsData = abi.encodePacked(postOpsData, lockBytes);
        (success,) = environment.call{value: msg.value}(postOpsData);
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

        // CASE: There are no donations, so just refund the solver credits
        } else if (donations.length == 0) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesCredit);
            return;

        // CASE: There are no donations, so just refund the solver credits and return
        } else if (donations[donations.length-1].cumulative == 0) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesCredit);
            return;

        // CASE: The donations exceed the liability
        } else if (donations[donations.length-1].cumulative * tx.gasprice > gasFeesSpent - gasFeesCredit) {
            SafeTransferLib.safeTransferETH(msg.sender, gasFeesSpent);

            uint256 totalDonations = donations[donations.length-1].cumulative * tx.gasprice;
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
                
                surplus = (donations[i].net * tx.gasprice * returnFactor) / 100;
                recipient = donations[i].recipient == address(0) ? user : donations[i].recipient;

                SafeTransferLib.safeTransferETH(recipient, surplus);

                unchecked{++i;}
            }
        }
    }

    function _update(
        SolverCall calldata sCall,
        SolverEscrow memory solverEscrow,
        uint256 gasWaterMark,
        uint256 result
    ) internal returns (uint256 gasRebate) {
        unchecked {
            uint256 gasUsed = gasWaterMark - gasleft();

            if (result & EscrowBits._FULL_REFUND != 0) {
                gasRebate = gasUsed + (sCall.data.length * CALLDATA_LENGTH_PREMIUM);
            } else if (result & EscrowBits._CALLDATA_REFUND != 0) {
                gasRebate = (sCall.data.length * CALLDATA_LENGTH_PREMIUM);
            } else if (result & EscrowBits._NO_USER_REFUND != 0) {
                // pass
            } else {
                revert("ERR-SE72 UncoveredResult");
            }

            if (gasRebate != 0) {
                // Calculate what the solver owes
                gasRebate *= tx.gasprice;

                gasRebate = gasRebate > solverEscrow.total ? solverEscrow.total : gasRebate;

                solverEscrow.total -= uint128(gasRebate);

                // NOTE: This will cause an error if you are simulating with a gasPrice of 0
                gasRebate /= tx.gasprice;

                // save the escrow data back into storage
                _escrowData[sCall.from] = solverEscrow;
            
            // Check if need to save escrowData due to nonce update but not gasRebate
            } else if (result & EscrowBits._NO_NONCE_UPDATE == 0) {
                _escrowData[sCall.from].nonce = solverEscrow.nonce;
            }
        }
    }

    function _verify(SolverOperation calldata solverOp, uint256 gasWaterMark, bool auctionAlreadyComplete)
        internal
        view
        returns (uint256 result, uint256 gasLimit, SolverEscrow memory solverEscrow)
    {
        // verify solver's signature
        if (_verifySignature(solverOp.call, solverOp.signature)) {
            // verify the solver has correct usercalldata and the solver escrow checks
            (result, gasLimit, solverEscrow) = _verifySolverOperation(solverOp);
        } else {
            (result, gasLimit) = (1 << uint256(SolverOutcome.InvalidSignature), 0);
            // solverEscrow returns null
        }

        result = _solverOpPreCheck(
            result, gasWaterMark, tx.gasprice, solverOp.call.maxFeePerGas, auctionAlreadyComplete
        );
    }

    function _getSolverHash(SolverCall calldata sCall) internal pure returns (bytes32 solverHash) {
        return keccak256(
            abi.encode(
                SOLVER_TYPE_HASH,
                sCall.from,
                sCall.to,
                sCall.value,
                sCall.gas,
                sCall.maxFeePerGas,
                sCall.nonce,
                sCall.deadline,
                sCall.controlCodeHash,
                sCall.userOpHash,
                sCall.bidsHash,
                keccak256(sCall.data)
            )
        );
    }

    function getSolverPayload(SolverCall calldata sCall) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getSolverHash(sCall));
    }

    function _verifySignature(SolverCall calldata sCall, bytes calldata signature) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getSolverHash(sCall)).recover(signature);
        return signer == sCall.from;
    }

    function _verifyBids(bytes32 bidsHash, BidData[] calldata bids) internal pure returns (bool validBid) {
        // NOTE: this should only occur after the solver's signature on the bidsHash is verified
        validBid = keccak256(abi.encode(bids)) == bidsHash;
    }

    function _verifySolverOperation(SolverOperation calldata solverOp)
        internal
        view
        returns (uint256 result, uint256 gasLimit, SolverEscrow memory solverEscrow)
    {
        solverEscrow = _escrowData[solverOp.call.from];

        // TODO big unchecked block - audit/review carefully
        unchecked {

            if (solverOp.call.nonce <= uint256(solverEscrow.nonce)) {
                result |= 1 << uint256(SolverOutcome.InvalidNonceUnder);
            } else if (solverOp.call.nonce > uint256(solverEscrow.nonce) + 1) {
                result |= 1 << uint256(SolverOutcome.InvalidNonceOver);

                // TODO: reconsider the jump up for gapped nonces? Intent is to mitigate dmg
                // potential inflicted by a hostile solver/builder.
                solverEscrow.nonce = uint32(solverOp.call.nonce);
            } else {
                ++solverEscrow.nonce;
            }

            if (solverEscrow.lastAccessed >= uint64(block.number)) {
                result |= 1 << uint256(SolverOutcome.PerBlockLimit);
            } else {
                solverEscrow.lastAccessed = uint64(block.number);
            }

            if (!_verifyBids(solverOp.call.bidsHash, solverOp.bids)) {
                result |= 1 << uint256(SolverOutcome.InvalidBidsHash);
            }

            gasLimit = (100)
                * (
                    solverOp.call.gas < EscrowBits.SOLVER_GAS_LIMIT
                        ? solverOp.call.gas
                        : EscrowBits.SOLVER_GAS_LIMIT
                ) / (100 + EscrowBits.SOLVER_GAS_BUFFER) + EscrowBits.FASTLANE_GAS_BUFFER;

            uint256 gasCost = (tx.gasprice * gasLimit) + (solverOp.call.data.length * CALLDATA_LENGTH_PREMIUM * tx.gasprice);

            // see if solver's escrow can afford tx gascost
            if (gasCost > solverEscrow.total - _withdrawalData[solverOp.call.from].escrowed) {
                // charge solver for calldata so that we can avoid vampire attacks from solver onto user
                result |= 1 << uint256(SolverOutcome.InsufficientEscrow);
            }

            // Verify that we can lend the solver their tx value
            if (solverOp.call.value > address(this).balance - (gasLimit * tx.gasprice)) {
                result |= 1 << uint256(SolverOutcome.CallValueTooHigh);
            }

            // subtract out the gas buffer since the solver's metaTx won't use it
            gasLimit -= EscrowBits.FASTLANE_GAS_BUFFER;
        }
    }

    function _solverOpWrapper(
        uint256 gasLimit,
        address environment,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        bytes32 lockBytes
    ) internal returns (SolverOutcome, uint256) {
        // address(this) = Atlas/Escrow
        // msg.sender = tx.origin

        // Get current Ether balance
        uint256 currentBalance = address(this).balance;
        bool success;

        bytes memory data = abi.encodeWithSelector(
            IExecutionEnvironment(environment).solverMetaTryCatch.selector, gasLimit, currentBalance, solverOp, dAppReturnData);
        
        data = abi.encodePacked(data, lockBytes);

        // Account for ETH borrowed by solver - repay with repayBorrowedEth() below
        _accData.ethBorrowed[solverOp.call.to] += solverOp.call.value;

        (success, data) = environment.call{value: solverOp.call.value}(data);
        
        // Check all borrowed ETH was repaid during solver call from Execution Env
        if(_accData.ethBorrowed[solverOp.call.to] != 0){
            revert FastLaneErrorsEvents.SolverMsgValueUnpaid();
        }

        if (success) {
            return (SolverOutcome.Success, address(this).balance - currentBalance);
        }
        bytes4 errorSwitch = bytes4(data);

        if (errorSwitch == SolverBidUnpaid.selector) {
            return (SolverOutcome.BidNotPaid, 0);
        } else if (errorSwitch == SolverMsgValueUnpaid.selector) {
            return (SolverOutcome.CallValueTooHigh, 0);
        } else if (errorSwitch == IntentUnfulfilled.selector) {
            return (SolverOutcome.IntentUnfulfilled, 0);
        } else if (errorSwitch == SolverOperationReverted.selector) {
            return (SolverOutcome.CallReverted, 0);
        } else if (errorSwitch == SolverFailedCallback.selector) {
            return (SolverOutcome.CallbackFailed, 0);
        } else if (errorSwitch == AlteredControlHash.selector) {
            return (SolverOutcome.InvalidControlHash, 0);
        } else if (errorSwitch == PreSolverFailed.selector) {
            return (SolverOutcome.PreSolverFailed, 0);
        } else if (errorSwitch == PostSolverFailed.selector) {
            return (SolverOutcome.IntentUnfulfilled, 0);
        } else {
            return (SolverOutcome.CallReverted, 0);
        }
    }

    function repayBorrowedEth(address borrower) external payable {
        uint256 debt = _accData.ethBorrowed[borrower];
        require(debt > 0, "ERR-E081 NoDebtToRepay");
        _accData.ethBorrowed[borrower] = debt - msg.value;
    }

    receive() external payable {}

    fallback() external payable {
        revert(); // no untracked balance transfers plz. (not that this fully stops it)
    }

    // BITWISE STUFF
    function _solverOpPreCheck(
        uint256 result,
        uint256 gasWaterMark,
        uint256 txGasPrice,
        uint256 maxFeePerGas,
        bool auctionAlreadyComplete
    ) internal pure returns (uint256) {
        if (auctionAlreadyComplete) {
            result |= 1 << uint256(SolverOutcome.LostAuction);
        }

        if (gasWaterMark < EscrowBits.VALIDATION_GAS_LIMIT + EscrowBits.SOLVER_GAS_LIMIT) {
            // Make sure to leave enough gas for dApp validation calls
            result |= 1 << uint256(SolverOutcome.UserOutOfGas);
        }

        if (txGasPrice > maxFeePerGas) {
            result |= 1 << uint256(SolverOutcome.GasPriceOverCap);
        }

        return result;
    }
}
