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

    uint256 constant private _ledgerLength = 6; // uint256(type(GasParty).max); // 6
    Ledger[_ledgerLength] public ledgers;
    AtlasLedger public atlasLedger;

    GasDonation[] internal _donations;
    AccountingData internal _accData;

    constructor(address _simulator) SafetyLocks(_simulator) {
        for (uint256 i; i < _ledgerLength; i++) {
            ledgers[i].ledgerStatus = LedgerStatus.Inactive; // init the storage vars
        }
    }

    function _initialAccounting() internal {
        // Note: assumes msg.sender == tx.origin
        if (msg.value > 0) {
            uint64 bundlerDeposit = uint64(msg.value / tx.gasprice);
            ledgers[uint256(GasParty.Bundler)] = Ledger({
                deposited: bundlerDeposit,
                withdrawn: 0,
                unfulfilled: 0,
                ledgerStatus: LedgerStatus.Surplus
            });

            atlasLedger = AtlasLedger({
                totalBorrowed: 0,
                totalDeposited: 0,
                totalRequested: 0,
                totalFulfilled: 0
            });

        } else {
            uint64 bundlerDeposit = uint64(msg.value / tx.gasprice);
            atlasLedger = AtlasLedger({
                totalBorrowed: 0,
                totalDeposited: bundlerDeposit,
                totalRequested: 0,
                totalFulfilled: bundlerDeposit
            });
        }
    }

    // NOTE: donations are simply deposits that have a different msg.sender than receiving party
    function _deposit(GasParty party, uint256 amt) internal returns (uint256 balanceOwed) {

        uint64 depositAmount = uint64(amt / tx.gasprice);
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];
        AtlasLedger memory aLedger = atlasLedger;

        if (pLedger.unfulfilled != 0) {
            if (pLedger.unfulfilled > depositAmount) {
                pLedger.unfulfilled -= depositAmount;
                aLedger.totalFulfilled += depositAmount;
            
            } else {
                uint64 fulfilled = pLedger.unfulfilled;
                depositAmount -= fulfilled;

                pLedger.deposited += depositAmount;
                pLedger.unfulfilled = 0; // -= fulfilled;

                aLedger.totalFulfilled += fulfilled;
                aLedger.totalDeposited += depositAmount;
            }

        } else {
            pLedger.deposited += depositAmount;
            aLedger.totalDeposited += depositAmount;
        }

        pLedger.ledgerStatus = _getLedgerStatus(pLedger);

        ledgers[partyIndex] = pLedger;
        atlasLedger = aLedger;

        if (pLedger.withdrawn >= pLedger.deposited) { // if unfulfilled > 0, deposits must be <= withdraws
            return (uint256(pLedger.unfulfilled) + uint256(pLedger.withdrawn)) - uint256(pLedger.deposited) * tx.gasprice;
        } else {
            return 0;
        }
    }


    function _borrow(GasParty party, uint256 amt) internal {

        uint64 amount = uint64(amt / tx.gasprice);
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];
        pLedger.withdrawn += amount;

        pLedger.ledgerStatus = _getLedgerStatus(pLedger);

        ledgers[partyIndex] = pLedger;
        atlasLedger.totalBorrowed += amount;
    }

    function _requestFrom(GasParty donor, GasParty recipient, uint256 amt) internal {

        AtlasLedger memory aLedger = atlasLedger;

        uint64 amount = uint64(amt / tx.gasprice);
        uint256 donorIndex = uint256(donor);
        uint256 recipientIndex = uint256(recipient);

        Ledger memory dLedger = ledgers[donorIndex];
        Ledger memory rLedger = ledgers[recipientIndex];

        if (dLedger.deposited > dLedger.withdrawn) {
            uint64 netBalance = dLedger.deposited - dLedger.withdrawn;
            if (netBalance > amount) {
                dLedger.withdrawn += amount;
                rLedger.deposited += amount;

                aLedger.totalRequested += amount;
                aLedger.totalFulfilled += amount;
            
            } else {
                dLedger.withdrawn = dLedger.deposited;
                dLedger.unfulfilled += amount - netBalance;
                rLedger.deposited += amount;

                aLedger.totalRequested += amount;
                aLedger.totalFulfilled += netBalance;
            }

        } else {
            dLedger.unfulfilled += amount;
            rLedger.deposited += amount;

            aLedger.totalRequested += amount;
        }

        dLedger.ledgerStatus = _getLedgerStatus(dLedger);
        rLedger.ledgerStatus = _getLedgerStatus(rLedger);

        ledgers[donorIndex] = dLedger;
        ledgers[recipientIndex] = rLedger;
        atlasLedger = aLedger;
    }

    function _depositDeficit(AtlasLedger memory aLedger, GasParty party, address partyAddress, uint256 deposit) internal returns (AtlasLedger memory, uint256 deficit) {
        uint64 depositAmount = uint64(deposit / tx.gasprice);
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];

        if (pLedger.unfulfilled != 0) {
            if (pLedger.unfulfilled > depositAmount) {
                pLedger.unfulfilled -= depositAmount;
                aLedger.totalFulfilled += depositAmount;
            
            } else {
                uint64 fulfilled = pLedger.unfulfilled;
                depositAmount -= fulfilled;

                pLedger.deposited += depositAmount;
                pLedger.unfulfilled = 0; // -= fulfilled;

                aLedger.totalFulfilled += fulfilled;
                aLedger.totalDeposited += depositAmount;
            }

        } else {
            pLedger.deposited += depositAmount;
            aLedger.totalDeposited += depositAmount;
        }

        if (pLedger.withdrawn + pLedger.unfulfilled > pLedger.deposited) { // if unfulfilled > 0, deposits must be <= withdraws
            deficit = ((uint256(pLedger.unfulfilled) + uint256(pLedger.withdrawn)) - uint256(pLedger.deposited)) * tx.gasprice;
        
        } else if (pLedger.deposited > pLedger.withdrawn + pLedger.unfulfilled) {
            deficit = 0;
            uint64 surplus = (pLedger.deposited - pLedger.unfulfilled) + pLedger.withdrawn;

            pLedger.deposited -= surplus;
            aLedger.totalDeposited -= surplus;

            SafeTransferLib.safeTransferETH(partyAddress, uint256(surplus) * tx.gasprice);
        
        } else {
            deficit = 0;
        }

        pLedger.ledgerStatus = _getLedgerStatus(pLedger);
        ledgers[partyIndex] = pLedger;

        return (aLedger, deficit);
    }

    function _validParty(address environment, GasParty party) internal returns (bool valid) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) {
            return false;
        }

        uint256 parties = 1 << uint256(party);
        uint256 activeParties = uint256(mLock.activeParties);

        if (activeParties & parties != parties) {
            activeParties |= parties;
            lock.activeParties = uint64(activeParties);
        }
        return true;
    }

    function _validParties(address environment, GasParty partyOne, GasParty partyTwo) internal returns (bool valid) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) {
            return false;
        }

        uint256 parties = 1 << uint256(partyOne) | 1 << uint256(partyTwo);
        uint256 activeParties = uint256(mLock.activeParties);

        if (activeParties & parties != parties) {
            activeParties |= parties;
            lock.activeParties = uint64(activeParties);
        }
        return true;
    }

    function _getLedgerStatus(Ledger memory pLedger) internal pure returns (LedgerStatus status) {
        uint256 deposited = uint256(pLedger.deposited);
        uint256 debts = uint256(pLedger.withdrawn) + uint256(pLedger.unfulfilled);
        if (deposited > debts) {
            status = LedgerStatus.Surplus;
        } else if (deposited < debts) {
            status = LedgerStatus.Deficit;
        } else {
            status = LedgerStatus.Balanced;
        }
    }

    // TODO: The balance checks on escrow that verify that the solver
    // paid back any msg.value that they borrowed are currently not set up 
    // to handle gas donations to the bundler from the solver.
    // THIS IS EXPLOITABLE - DO NOT USE THIS CONTRACT IN PRODUCTION
    // This attack vector will be addressed explicitly once the gas 
    // reimbursement mechanism is finalized.
    function donateToBundler(address surplusRecipient) external payable {
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