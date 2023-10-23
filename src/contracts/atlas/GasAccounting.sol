//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {SafetyLocks} from "../atlas/SafetyLocks.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";


import {EscrowBits} from "../libraries/EscrowBits.sol";
import {GasPartyMath} from "../libraries/GasParties.sol";

import "forge-std/Test.sol";

abstract contract GasAccounting is SafetyLocks {
    using SafeTransferLib for ERC20;
    using GasPartyMath for GasParty;
    using GasPartyMath for uint256;

    uint256 constant public BUNDLER_PREMIUM = 105; // the amount over cost that bundlers get paid
    uint256 constant public BUNDLER_BASE = 100;

    mapping(address => EscrowAccountData) internal _escrowAccountData;

    constructor(address _simulator) SafetyLocks(_simulator) {}

    // NOTE: donations are simply deposits that have a different msg.sender than receiving party
    function _deposit(GasParty party, uint256 amt) internal returns (uint256 balanceOwed) {

        int64 depositAmount = int64(uint64(amt / tx.gasprice));
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];
        require(pLedger.status != LedgerStatus.Finalized, "ERR-GA002, LedgerFinalized");

        if (pLedger.status == LedgerStatus.Inactive) pLedger.status = LedgerStatus.Active;

        pLedger.balance += depositAmount;
        
        balanceOwed = pLedger.balance < 0 ? uint256(uint64(-1 * pLedger.balance)) : 0;

        ledgers[partyIndex] = pLedger;
    }


    function _borrow(GasParty party, uint256 amt) internal {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch. 

        int64 borrowAmount = int64(uint64(amt / tx.gasprice))+1;
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];
        require(uint256(pLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA003, LedgerFinalized");
        if (pLedger.status == LedgerStatus.Inactive) pLedger.status = LedgerStatus.Active;

        pLedger.balance -= borrowAmount;
        
        ledgers[partyIndex] = pLedger;
    }

    function _use(GasParty party, address partyAddress, uint256 amt) internal {
        
        int64 amount = int64(uint64(amt / tx.gasprice))+1;
        uint256 partyIndex = uint256(party);

        Ledger memory pLedger = ledgers[partyIndex];

        require(uint256(pLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA004, LedgerBalancing");
        if (pLedger.status == LedgerStatus.Inactive) pLedger.status = LedgerStatus.Active;
        
        if (pLedger.requested > 0) {
            if (amount > pLedger.requested) {
                amount -= pLedger.requested;
                pLedger.requested = 0;
            } else {
                pLedger.requested -= amount;
                ledgers[partyIndex] = pLedger;
                return;
            }
        }

        if (pLedger.contributed > 0) {
            if (amount > pLedger.contributed) {
                amount -= pLedger.contributed;
                pLedger.contributed = 0;
            } else {
                pLedger.contributed -= amount;
                ledgers[partyIndex] = pLedger;
                return;
            }
        }

        // Avoid the storage read for as long as possible
        if (pLedger.balance > 0) {
            if (amount > pLedger.balance) {
                amount -= pLedger.balance;
                pLedger.balance = 0;
            } else {
                pLedger.balance -= amount;
                ledgers[partyIndex] = pLedger;
                return;
            }
        }

        amt = uint256(uint64(amount+1)) * tx.gasprice;
        uint256 balance = uint256(_escrowAccountData[partyAddress].balance);

        if (balance > amt) {
            pLedger.balance -= amount;
            ledgers[partyIndex] = pLedger;
            return;
        }

        revert("ERR-GA022 InsufficientFunds");
    }

    function _requestFrom(GasParty donor, GasParty recipient, uint256 amt) internal {
        // TODO: different parties will be ineligible to request funds from once their phase is over.
        // We need to add a phase check to verify this. 

        int64 amount = int64(uint64(amt / tx.gasprice));

        uint256 donorIndex = uint256(donor);
        uint256 recipientIndex = uint256(recipient);

        Ledger memory dLedger = ledgers[donorIndex];
        Ledger memory rLedger = ledgers[recipientIndex];

        require(uint256(dLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA004, LedgerBalancing");
        if (dLedger.status == LedgerStatus.Inactive) dLedger.status = LedgerStatus.Active;

        require(rLedger.status != LedgerStatus.Finalized, "ERR-GA005, LedgerFinalized");
        if (rLedger.status == LedgerStatus.Inactive) rLedger.status = LedgerStatus.Active;

        dLedger.contributed -= amount;
        rLedger.requested -= amount;

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
        if (dLedger.status == LedgerStatus.Inactive) dLedger.status = LedgerStatus.Active;

        require(rLedger.status != LedgerStatus.Finalized, "ERR-GA007, LedgerFinalized");
        if (rLedger.status == LedgerStatus.Inactive) rLedger.status = LedgerStatus.Active;

        dLedger.balance -= amount;
        dLedger.contributed += amount;
        rLedger.requested += amount;

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
            if (activeParties & 1<<(i+1) == 0){
                unchecked{++i;}
                continue;
            }

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

    function _balance(uint256 accruedGasRebate, address user, address dapp, address winningSolver, address bundler) internal {
        Lock memory mLock = lock;

        int64 totalRequests;
        int64 totalContributions;
        int64 totalBalanceDelta;

        uint256 activeParties = uint256(mLock.activeParties);

        Ledger[] memory mLedgers = new Ledger[](_ledgerLength);
        for (uint256 i; i < _ledgerLength;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }

            Ledger memory pLedger = ledgers[i];

            if (i == uint256(GasParty.Bundler)) {
                pLedger.balance += int64(uint64(accruedGasRebate));
            }

            totalBalanceDelta += pLedger.balance;
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

        {
        int64 surplus = totalRequests + totalContributions;
        require(surplus > 0, "ERR-GA014a, MissingFunds");

        // TODO: Adjust to accomodate the direction of rounding errors. 
        int64 atlasBalanceDelta = int64(uint64((address(this).balance - msg.value) / tx.gasprice)) - int64(mLock.startingBalance);
        require(atlasBalanceDelta >= surplus + totalBalanceDelta);

        console.log("");
        console.log("--");
        console.log("gasRebate  :", accruedGasRebate);
        _logInt64("surplus      :", surplus);
        _logInt64("gasRemainder :", gasRemainder);
        _logInt64("totalRequests:", totalRequests);
        _logInt64("contributions:", totalContributions);
        console.log("--");
        console.log("balances");
        }
        
        
        for (uint256 i; i < _ledgerLength;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }
    
            address partyAddress = _partyAddress(i, user, dapp, winningSolver, bundler);

            Ledger memory pLedger = mLedgers[i];

            EscrowAccountData memory escrowData = _escrowAccountData[partyAddress];

            
            console.log("");
            console.log("Party:", _partyName(i));
            console.log("-");
            _logInt64("netBalance  :", pLedger.balance);
            _logInt64("requested   :", pLedger.requested);
            _logInt64("contributed :", pLedger.contributed);
            

            // CASE: Some Requests still in Deficit
            if (totalRequests < 0 && pLedger.contributed > 0) {
                if (totalRequests + pLedger.contributed > 0) {
                    pLedger.contributed += totalRequests; // a subtraction since totalRequests is negative
                    totalRequests = 0;
                } else {
                    totalRequests += pLedger.contributed;
                    pLedger.contributed = 0;
                }
            }

            // CASE: Some Contributions still in Deficit (means surplus in Requests)
            if (totalContributions < 0 && pLedger.requested > 0) {
                if (pLedger.requested > totalContributions) {
                    pLedger.requested -= totalContributions;
                    totalContributions = 0;
                } else {
                    totalContributions -= pLedger.requested;
                    pLedger.requested = 0;
                }
            }


            int64 partyBalanceDelta = pLedger.balance + pLedger.contributed - pLedger.requested;

            
            _logInt64("pDelta      :", partyBalanceDelta);
            console.log("-");
            console.log("Starting Bal:", escrowData.balance);
            

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

            
            console.log("Ending Bal  :", escrowData.balance);
            console.log("-");
            

            unchecked{++i;}
        }
    }

    // TODO: Unroll this - just doing it for now to improve readability
    function _partyAddress(uint256 index, address user, address dapp, address winningSolver, address bundler) internal view returns (address) {
        GasParty party = GasParty(index);
        if (party == GasParty.DApp) return dapp;
        if (party == GasParty.User) return user;
        if (party == GasParty.Solver) return winningSolver;
        if (party == GasParty.Bundler) return bundler; // <3
        if (party == GasParty.Builder) return block.coinbase;
        return address(this);
    }

    
    // for testing purposes
    function _partyName(uint256 index) internal pure returns (string memory) {
        GasParty party = GasParty(index);
        if (party == GasParty.DApp) return "dApp";
        if (party == GasParty.User) return "user";
        if (party == GasParty.Solver) return "solver";
        if (party == GasParty.Bundler) return "bundler"; 
        if (party == GasParty.Builder) return "builder";
        return "unknown";
    }

    function _logInt64(string memory pretext, int64 i) internal view {
        if (i < 0) console.log(string.concat(pretext, " -"), uint64(-1 * i));
        else console.log(string.concat(pretext, " +"), uint64(i));
    }
    

    function _validParty(address environment, GasParty party) internal returns (bool valid) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) {
            return false;
        }

        uint256 activeParties = uint256(mLock.activeParties);

        if (activeParties.isInactive(party)) {
            activeParties = activeParties.markActive(party);
            lock.activeParties = uint16(activeParties);
        }
        return true;
    }

    function _validParties(address environment, GasParty partyOne, GasParty partyTwo) internal returns (bool valid) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) {
            return false;
        }

        uint256 parties = partyOne.toBit() | partyTwo.toBit();
        uint256 activeParties = uint256(mLock.activeParties);

        if (activeParties & parties != parties) {
            activeParties |= parties;
            lock.activeParties = uint16(activeParties);
        }
        return true;
    }

    function contribute(GasParty recipient) external payable {
        require(_validParty(msg.sender, recipient), "ERR-GA020 InvalidEnvironment"); 

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        uint256 pIndex = uint256(recipient);
        Ledger memory pLedger = ledgers[pIndex];

        require(pLedger.status != LedgerStatus.Finalized, "ERR-GA021, LedgerFinalized");
        if (pLedger.status == LedgerStatus.Inactive) pLedger.status = LedgerStatus.Active;

        if (pLedger.requested < 0) {
            // CASE: still in deficit
            if (pLedger.requested + amount < 0) {
                pLedger.requested += amount;
                amount = 0;
            
            // CASE: surplus
            } else {
                amount += pLedger.requested;
                pLedger.requested = 0;
            }
        }

        if (amount != 0) pLedger.contributed += amount;
        
        ledgers[pIndex] = pLedger;
    }

    function deposit(GasParty party) external payable {
        require(_validParty(msg.sender, party), "ERR-GA022 InvalidEnvironment");

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        uint256 pIndex = uint256(party);
        Ledger memory pLedger = ledgers[pIndex];

        require(pLedger.status != LedgerStatus.Finalized, "ERR-GA023 LedgerFinalized");
        if (pLedger.status == LedgerStatus.Inactive) pLedger.status = LedgerStatus.Active;

        pLedger.balance += amount;
        
        ledgers[pIndex] = pLedger;
    }

    // NOTE: DAPPs can gain malicious access to these funcs if they want to, but attacks beyond
    // the approved amounts will only lead to a revert.  
    // Bundlers must make sure the DApp hasn't maliciously upgraded their contract to avoid wasting gas. 
    function contributeTo(GasParty donor, GasParty recipient, uint256 amt) external {
        require(_validParties(msg.sender, donor, recipient), "ERR-GA021 InvalidEnvironment");
        _contributeTo(donor, recipient, amt);
    }

    function requestFrom(GasParty donor, GasParty recipient, uint256 amt) external {
        require(_validParties(msg.sender, donor, recipient), "ERR-GA022 InvalidEnvironment"); 
        _requestFrom(donor, recipient, amt);
    }

    function finalize(GasParty party, address partyAddress) external returns (bool) {
        require(_validParty(msg.sender, party), "ERR-GA024 InvalidEnvironment");
        require(party != GasParty.Solver, "ERR-GA025 SolverMustReconcile");

        uint256 pIndex = uint256(party);
        Ledger memory pLedger = ledgers[pIndex];

        if (pLedger.status == LedgerStatus.Finalized) return false;
        
        if (pLedger.contributed + pLedger.requested < 0) return false;

        uint256 grossBalance = uint256(_escrowAccountData[partyAddress].balance);

        if (int64(uint64(grossBalance / tx.gasprice)) + pLedger.balance - 1 < 0) return false;
        
        pLedger.status = LedgerStatus.Finalized;
        ledgers[pIndex] = pLedger;

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