//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {SafetyLocks} from "../atlas/SafetyLocks.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

import "forge-std/Test.sol";

abstract contract GasAccounting is SafetyLocks {
    using SafeTransferLib for ERC20;

    uint256 constant public BUNDLER_PREMIUM = 110; // the amount over cost that bundlers get paid
    uint256 constant public BUNDLER_BASE = 100;

    GasDonation[] internal _donations;
    AccountingData internal _accData;

    constructor(address _simulator) SafetyLocks(_simulator) {}

    // TODO: The balance checks on escrow that verify that the solver
    // paid back any msg.value that they borrowed are currently not set up 
    // to handle gas donations to the bundler from the solver.
    // THIS IS EXPLOITABLE - DO NOT USE THIS CONTRACT IN PRODUCTION
    // This attack vector will be addressed explicitly once the gas 
    // reimbursement mechanism is finalized.
    function donateToBundler(address surplusRecipient) external payable {
        console.log("Donate to bundler called");
        console.log("donateToBundler: msg.value:", msg.value);
        console.log("donating to addr:", surplusRecipient);
        // NOTE: All donations in excess of 10% greater than cost are forwarded
        // to the surplusReceiver. 

        // TODO: Consider making this a higher donation threshold to avoid ddos attacks
        if (msg.value == 0) {
            return;
        }

        uint32 gasRebate;

        uint256 debt = _accData.ethBorrowed[surplusRecipient];
        if (debt > 0) {
            if (debt > msg.value) {
                _accData.ethBorrowed[surplusRecipient] = debt - msg.value;
                return;
            } 
            
            if (debt == msg.value) {
                _accData.ethBorrowed[surplusRecipient] = 0;
                return;  
            }
            
            gasRebate = uint32((msg.value - debt) / tx.gasprice);
            

        } else {
            gasRebate = uint32(msg.value / tx.gasprice);
        }
        
        console.log("donateToBundler: tx.gasprice:", tx.gasprice);
        console.log("donateToBundler: gasRebate:", gasRebate);

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

    function repayBorrowedEth(address borrower) external payable {
        uint256 debt = _accData.ethBorrowed[borrower];
        require(debt > 0, "ERR-E081 NoDebtToRepay");
        _accData.ethBorrowed[borrower] = debt - msg.value;
    }

    function getAmountOwed(address borrower) external payable returns (uint256 amountOwed) {
        // Any msg.value will go towards the debt. 
        amountOwed = _accData.ethBorrowed[borrower];

        if (amountOwed == 0) {
            if (msg.value > 0) {
                SafeTransferLib.safeTransferETH(msg.sender, msg.value);
            }
            return 0;
        }

        if (msg.value > 0) {
            if (msg.value > amountOwed) {
                _accData.ethBorrowed[borrower] = 0;
                SafeTransferLib.safeTransferETH(msg.sender, msg.value - amountOwed);
                return 0;
            }

            if (msg.value == amountOwed) {
                _accData.ethBorrowed[borrower] = 0;
                return 0;
            }

            amountOwed -= msg.value;
            _accData.ethBorrowed[borrower] = amountOwed;
            return amountOwed;
        }

        return amountOwed;
    }
}