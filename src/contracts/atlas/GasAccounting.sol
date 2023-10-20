//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {SafetyLocks} from "../atlas/SafetyLocks.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";


import {EscrowBits} from "../libraries/EscrowBits.sol";

import "forge-std/Test.sol";

abstract contract GasAccounting is SafetyLocks {
    using SafeTransferLib for ERC20;

    uint256 constant public BUNDLER_PREMIUM = 105; // the amount over cost that bundlers get paid
    uint256 constant public BUNDLER_BASE = 100;

    mapping(address => EscrowAccountData) internal _escrowAccountData;

    GasDonation[] internal _donations;
    AccountingData internal _accData;

    constructor(address _simulator) SafetyLocks(_simulator) {}

    // NOTE: donations are simply deposits that have a different msg.sender than receiving party
    function _deposit(GasParty party, uint256 amt) internal returns (uint256 balanceOwed) {

        int64 depositAmount = int64(uint64(amt / tx.gasprice));
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];
        require(pLedger.status != LedgerStatus.Finalized, "ERR-GA002, LedgerFinalized");

        if (pLedger.status == LedgerStatus.Unknown) pLedger.status = LedgerStatus.Active;

        pLedger.balance += depositAmount;
        
        balanceOwed = pLedger.balance < 0 ? uint256(uint64(-1 * pLedger.balance)) : 0;

        ledgers[partyIndex] = pLedger;
    }


    function _borrow(GasParty party, uint256 amt) internal {

        int64 borrowAmount = int64(uint64(amt / tx.gasprice));
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];
        require(pLedger.status != LedgerStatus.Finalized, "ERR-GA003, LedgerFinalized");
        if (pLedger.status == LedgerStatus.Unknown) pLedger.status = LedgerStatus.Active;

        pLedger.balance -= borrowAmount;
        
        ledgers[partyIndex] = pLedger;
    }

    function _requestFrom(GasParty donor, GasParty recipient, uint256 amt) internal {

        int64 amount = int64(uint64(amt / tx.gasprice));

        uint256 donorIndex = uint256(donor);
        uint256 recipientIndex = uint256(recipient);

        Ledger memory dLedger = ledgers[donorIndex];
        Ledger memory rLedger = ledgers[recipientIndex];

        require(dLedger.status != LedgerStatus.Finalized, "ERR-GA004, LedgerFinalized");
        if (dLedger.status == LedgerStatus.Unknown) dLedger.status = LedgerStatus.Active;

        require(rLedger.status != LedgerStatus.Finalized, "ERR-GA005, LedgerFinalized");
        if (rLedger.status == LedgerStatus.Unknown) rLedger.status = LedgerStatus.Active;

        dLedger.contributed -= amount;
        rLedger.requested += amount;

        ledgers[donorIndex] = dLedger;
        ledgers[recipientIndex] = rLedger;
    }

    function _contributeTo(GasParty donor, GasParty recipient, uint256 amt) internal {

        int64 amount = int64(uint64(amt / tx.gasprice));

        uint256 donorIndex = uint256(donor);
        uint256 recipientIndex = uint256(recipient);

        Ledger memory dLedger = ledgers[donorIndex];
        Ledger memory rLedger = ledgers[recipientIndex];

        require(dLedger.status != LedgerStatus.Finalized, "ERR-GA006, LedgerFinalized");
        if (dLedger.status == LedgerStatus.Unknown) dLedger.status = LedgerStatus.Active;

        require(rLedger.status != LedgerStatus.Finalized, "ERR-GA007, LedgerFinalized");
        if (rLedger.status == LedgerStatus.Unknown) rLedger.status = LedgerStatus.Active;

        dLedger.contributed += amount;
        rLedger.requested -= amount;

        ledgers[donorIndex] = dLedger;
        ledgers[recipientIndex] = rLedger;
    }

    function validateBalances() external view returns (bool valid) {
        valid = ledgers[uint256(GasParty.Solver)].status == LedgerStatus.Finalized && _isInSurplus(msg.sender);
    }

    function _isInSurplus(address environment) internal view returns (bool) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) return false;

        int64 atlasBalanceDelta = int64(mLock.startingBalance) - int64(uint64(address(this).balance / tx.gasprice));

        int64 balanceDelta;
        int64 totalRequests;
        int64 totalContributions;

        uint256 activeParties = uint256(mLock.activeParties);
        Ledger memory pLedger;
        for (uint256 i; i < _ledgerLength;) {
            // If party has not been touched, skip it
            if (activeParties & 1<<i == 0) continue;

            pLedger = ledgers[i];

            balanceDelta += pLedger.balance;
            totalRequests += pLedger.requested;
            totalContributions += pLedger.contributed;

            unchecked{++i;}
        }

        // If atlas balance is lower than expected, return false
        if (atlasBalanceDelta < balanceDelta) return false;

        // If the requests have not yet been met, return false
        if (totalRequests > totalContributions) return false;

        // Otherwise return true
        return true;
    }

    function _balance(uint256 accruedGasRebate, address user, address dapp, address winningSolver) internal {
        Lock memory mLock = lock;

        int64 totalRequests;
        int64 totalContributions;

        uint256 activeParties = uint256(mLock.activeParties);

        Ledger[] memory mLedgers = new Ledger[](_ledgerLength);
        Ledger memory pLedger;
        for (uint256 i; i < _ledgerLength;) {
            // If party has not been touched, skip it
            if (activeParties & 1<<i == 0) continue;

            pLedger = ledgers[i];

            totalRequests += pLedger.requested;
            totalContributions += pLedger.contributed;

            mLedgers[i] = pLedger;

            ledgers[i] = Ledger({
                balance: 0,
                contributed: 0,
                requested: 0,
                status: LedgerStatus.Inactive
            });

            unchecked{++i;}
        }

        int64 gasRemainder = int64(uint64(gasleft() + accruedGasRebate + 20_000));

        // Reduce the bundler's gas request by the unused gas
        mLedgers[uint256(GasParty.Bundler)].requested += gasRemainder;
        totalRequests += gasRemainder;

        int64 surplus = totalRequests + totalContributions;
        require(surplus > 0, "ERR-GA014, MissingFunds");

        for (uint256 i; i < _ledgerLength;) {
            // If party has not been touched, skip it
            if (activeParties & 1<<i == 0) continue;

            address partyAddress = _partyAddress(i, user, dapp, winningSolver);

            pLedger = mLedgers[i];

            EscrowAccountData memory escrowData = _escrowAccountData[partyAddress];

            int64 partyBalanceDelta = pLedger.balance + pLedger.contributed - pLedger.requested; 
            if (partyBalanceDelta < 0) {
                escrowData.balance -= (uint128(uint64(partyBalanceDelta * -1)) * uint128(tx.gasprice));
            } else {
                escrowData.balance += (uint128(uint64(partyBalanceDelta)) * uint128(tx.gasprice));
            }

            if (i == uint256(GasParty.Solver)) {
                ++escrowData.nonce;
            }

            escrowData.lastAccessed = uint64(block.number);

            _escrowAccountData[partyAddress] = escrowData;

            unchecked{++i;}
        }
    }

    // TODO: Unroll this - just doing it for now to improve readability
    function _partyAddress(uint256 index, address user, address dapp, address winningSolver) internal view returns (address) {
        GasParty party = GasParty(index);
        if (party == GasParty.DApp) return dapp;
        if (party == GasParty.User) return user;
        if (party == GasParty.Solver) return winningSolver;
        if (party == GasParty.Bundler) return tx.origin; // <3
        if (party == GasParty.Builder) return block.coinbase;
        return address(this);
        
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
            lock.activeParties = uint16(activeParties);
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
            lock.activeParties = uint16(activeParties);
        }
        return true;
    }

    function reconcile(address environment, address searcherFrom, uint256 maxApprovedGasSpend) external payable returns (bool) {
        // NOTE: approvedAmount is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe.  This will be subtracted later - tx will revert here if there isn't enough. 
        if (!_validParty(environment, GasParty.Solver)) {
            return false;
        }

        uint256 partyIndex = uint256(GasParty.Solver);

        Ledger memory pLedger = ledgers[partyIndex];
        if (pLedger.status == LedgerStatus.Finalized) {
            return false;
        }

        if (pLedger.status == LedgerStatus.Unknown) pLedger.status = LedgerStatus.Active;

        if (msg.value != 0) {
            int64 amount = int64(uint64((msg.value) / tx.gasprice));
            pLedger.balance += amount;
        }

        if (maxApprovedGasSpend != 0) {
            uint256 solverSurplusBalance = uint256(_escrowAccountData[searcherFrom].balance) - (EscrowBits.SOLVER_GAS_LIMIT * tx.gasprice + 1);
            maxApprovedGasSpend = maxApprovedGasSpend > solverSurplusBalance ? solverSurplusBalance : maxApprovedGasSpend;
        

            int64 gasAllowance = int64(uint64(maxApprovedGasSpend / tx.gasprice));

            if (pLedger.balance < 0) {
                if (gasAllowance < pLedger.balance) {
                    return false;
                }
                gasAllowance += pLedger.balance; // note that .balance is a negative number so this is a subtraction
            }

            pLedger.contributed += gasAllowance; // note that surplus .contributed is refunded to the party
            pLedger.balance -= gasAllowance;
        }

        if (pLedger.contributed < 0) {
            return false;
        }
        
        pLedger.status = LedgerStatus.Finalized; // no additional requests can be made to this party
        ledgers[partyIndex] = pLedger;
        return true;
    }
}