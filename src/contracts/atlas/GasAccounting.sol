//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {SafetyLocks} from "../atlas/SafetyLocks.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";


import {EscrowBits} from "../libraries/EscrowBits.sol";
import {PartyMath} from "../libraries/GasParties.sol";

import "forge-std/Test.sol";

abstract contract GasAccounting is SafetyLocks {
    using SafeTransferLib for ERC20;
    using PartyMath for Party;
    using PartyMath for uint256;

    uint256 constant public BUNDLER_PREMIUM = 105; // the amount over cost that bundlers get paid
    uint256 constant public BUNDLER_BASE = 100;

    mapping(address => EscrowAccountData) internal _escrowAccountData;

    constructor(address _simulator) SafetyLocks(_simulator) {}

    // NOTE: donations are simply deposits that have a different msg.sender than receiving party
    function _deposit(Party party, uint256 amt) internal returns (uint256 balanceOwed) {

        int64 depositAmount = int64(uint64(amt / tx.gasprice));
        uint256 partyIndex = uint256(party);

        Ledger memory partyLedger = ledgers[partyIndex];
        require(partyLedger.status != LedgerStatus.Finalized, "ERR-GA002, LedgerFinalized");

        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;

        partyLedger.balance += depositAmount;
        
        balanceOwed = partyLedger.balance < 0 ? uint256(uint64(-1 * partyLedger.balance)) : 0;

        ledgers[partyIndex] = partyLedger;
    }


    function _borrow(Party party, uint256 amt) internal {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch. 

        int64 borrowAmount = int64(uint64(amt / tx.gasprice))+1;
        uint256 partyIndex = uint256(party);

        Ledger memory partyLedger = ledgers[partyIndex];
        require(uint256(partyLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA003, LedgerFinalized");
        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;

        partyLedger.balance -= borrowAmount;
        
        ledgers[partyIndex] = partyLedger;
    }

    function _use(Party party, address partyAddress, uint256 amt) internal {
        
        int64 amount = int64(uint64(amt / tx.gasprice))+1;
        uint256 partyIndex = uint256(party);

        Ledger memory partyLedger = ledgers[partyIndex];

        require(uint256(partyLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA004, LedgerBalancing");
        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;
        
        if (partyLedger.requested > 0) {
            if (amount > partyLedger.requested) {
                amount -= partyLedger.requested;
                partyLedger.requested = 0;
            } else {
                partyLedger.requested -= amount;
                ledgers[partyIndex] = partyLedger;
                return;
            }
        }

        if (partyLedger.contributed > 0) {
            if (amount > partyLedger.contributed) {
                amount -= partyLedger.contributed;
                partyLedger.contributed = 0;
            } else {
                partyLedger.contributed -= amount;
                ledgers[partyIndex] = partyLedger;
                return;
            }
        }

        // Avoid the storage read for as long as possible
        if (partyLedger.balance > 0) {
            if (amount > partyLedger.balance) {
                amount -= partyLedger.balance;
                partyLedger.balance = 0;
            } else {
                partyLedger.balance -= amount;
                ledgers[partyIndex] = partyLedger;
                return;
            }
        }

        amt = uint256(uint64(amount+1)) * tx.gasprice;
        uint256 balance = uint256(_escrowAccountData[partyAddress].balance);

        if (balance > amt) {
            partyLedger.balance -= amount;
            ledgers[partyIndex] = partyLedger;
            return;
        }

        revert("ERR-GA022 InsufficientFunds");
    }

    function _requestFrom(Party donor, Party recipient, uint256 amt) internal {
        // TODO: different parties will be ineligible to request funds from once their phase is over.
        // We need to add a phase check to verify this. 

        int64 amount = int64(uint64(amt / tx.gasprice));

        uint256 donorIndex = uint256(donor);
        uint256 recipientIndex = uint256(recipient);

        Ledger memory donorLedger = ledgers[donorIndex];
        Ledger memory recipientLedger = ledgers[recipientIndex];

        require(uint256(donorLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA004, LedgerBalancing");
        if (donorLedger.status == LedgerStatus.Inactive) donorLedger.status = LedgerStatus.Active;

        require(recipientLedger.status != LedgerStatus.Finalized, "ERR-GA005, LedgerFinalized");
        if (recipientLedger.status == LedgerStatus.Inactive) recipientLedger.status = LedgerStatus.Active;

        donorLedger.contributed -= amount;
        recipientLedger.requested -= amount;

        ledgers[donorIndex] = donorLedger;
        ledgers[recipientIndex] = recipientLedger;
    }

    function _contributeTo(Party donor, Party recipient, uint256 amt) internal {

        int64 amount = int64(uint64(amt / tx.gasprice));

        uint256 donorIndex = uint256(donor);
        uint256 recipientIndex = uint256(recipient);

        Ledger memory donorLedger = ledgers[donorIndex];
        Ledger memory recipientLedger = ledgers[recipientIndex];

        require(donorLedger.status != LedgerStatus.Finalized, "ERR-GA006, LedgerFinalized");
        if (donorLedger.status == LedgerStatus.Inactive) donorLedger.status = LedgerStatus.Active;

        require(recipientLedger.status != LedgerStatus.Finalized, "ERR-GA007, LedgerFinalized");
        if (recipientLedger.status == LedgerStatus.Inactive) recipientLedger.status = LedgerStatus.Active;

        donorLedger.balance -= amount;
        donorLedger.contributed += amount;
        recipientLedger.requested += amount;

        ledgers[donorIndex] = donorLedger;
        ledgers[recipientIndex] = recipientLedger;
    }

    // Returns true if Solver status is Finalized and the caller (Execution Environment) is in surplus
    function validateBalances() external view returns (bool valid) {
        valid = ledgers[uint256(Party.Solver)].status == LedgerStatus.Finalized && _isInSurplus(msg.sender);
    }

    function _isInSurplus(address environment) internal view returns (bool) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) return false;

        int64 atlasBalanceDelta = int64(mLock.startingBalance) - int64(uint64(address(this).balance / tx.gasprice));

        int64 balanceDelta;
        int64 totalRequests;
        int64 totalContributions;

        uint256 activeParties = uint256(mLock.activeParties);
        Ledger memory partyLedger;
        for (uint256 i; i < _ledgerLength;) {
            // If party has not been touched, skip it
            if (activeParties & 1<<(i+1) == 0){
                unchecked{++i;}
                continue;
            }

            partyLedger = ledgers[i];

            balanceDelta += partyLedger.balance;
            totalRequests += partyLedger.requested;
            totalContributions += partyLedger.contributed;

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

            Ledger memory partyLedger = ledgers[i];

            if (i == uint256(Party.Bundler)) {
                partyLedger.balance += int64(uint64(accruedGasRebate));
            }

            totalBalanceDelta += partyLedger.balance;
            totalRequests += partyLedger.requested;
            totalContributions += partyLedger.contributed;

            mLedgers[i] = partyLedger;

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
        mLedgers[uint256(Party.Bundler)].requested += gasRemainder;
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

            Ledger memory partyLedger = mLedgers[i];

            EscrowAccountData memory escrowData = _escrowAccountData[partyAddress];

            
            console.log("");
            console.log("Party:", _partyName(i));
            console.log("-");
            _logInt64("netBalance  :", partyLedger.balance);
            _logInt64("requested   :", partyLedger.requested);
            _logInt64("contributed :", partyLedger.contributed);
            

            // CASE: Some Requests still in Deficit
            if (totalRequests < 0 && partyLedger.contributed > 0) {
                if (totalRequests + partyLedger.contributed > 0) {
                    partyLedger.contributed += totalRequests; // a subtraction since totalRequests is negative
                    totalRequests = 0;
                } else {
                    totalRequests += partyLedger.contributed;
                    partyLedger.contributed = 0;
                }
            }

            // CASE: Some Contributions still in Deficit (means surplus in Requests)
            if (totalContributions < 0 && partyLedger.requested > 0) {
                if (partyLedger.requested > totalContributions) {
                    partyLedger.requested -= totalContributions;
                    totalContributions = 0;
                } else {
                    totalContributions -= partyLedger.requested;
                    partyLedger.requested = 0;
                }
            }


            int64 partyBalanceDelta = partyLedger.balance + partyLedger.contributed - partyLedger.requested;

            
            _logInt64("pDelta      :", partyBalanceDelta);
            console.log("-");
            console.log("Starting Bal:", escrowData.balance);
            

            if (partyBalanceDelta < 0) {
                escrowData.balance -= (uint128(uint64(partyBalanceDelta * -1)) * uint128(tx.gasprice));
            
            } else {
                escrowData.balance += (uint128(uint64(partyBalanceDelta)) * uint128(tx.gasprice));
            }

            if (i == uint256(Party.Solver)) {
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
        Party party = Party(index);
        if (party == Party.DApp) return dapp;
        if (party == Party.User) return user;
        if (party == Party.Solver) return winningSolver;
        if (party == Party.Bundler) return bundler; // <3
        if (party == Party.Builder) return block.coinbase;
        return address(this);
    }

    
    // for testing purposes
    function _partyName(uint256 index) internal pure returns (string memory) {
        Party party = Party(index);
        if (party == Party.DApp) return "dApp";
        if (party == Party.User) return "user";
        if (party == Party.Solver) return "solver";
        if (party == Party.Bundler) return "bundler"; 
        if (party == Party.Builder) return "builder";
        return "unknown";
    }

    function _logInt64(string memory pretext, int64 i) internal view {
        if (i < 0) console.log(string.concat(pretext, " -"), uint64(-1 * i));
        else console.log(string.concat(pretext, " +"), uint64(i));
    }
    

    function _validParty(address environment, Party party) internal returns (bool valid) {
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

    function _validParties(address environment, Party partyOne, Party partyTwo) internal returns (bool valid) {
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

    function contribute(Party recipient) external payable {
        require(_validParty(msg.sender, recipient), "ERR-GA020 InvalidEnvironment"); 

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        uint256 pIndex = uint256(recipient);
        Ledger memory partyLedger = ledgers[pIndex];

        require(partyLedger.status != LedgerStatus.Finalized, "ERR-GA021, LedgerFinalized");
        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;

        if (partyLedger.requested < 0) {
            // CASE: still in deficit
            if (partyLedger.requested + amount < 0) {
                partyLedger.requested += amount;
                amount = 0;
            
            // CASE: surplus
            } else {
                amount += partyLedger.requested;
                partyLedger.requested = 0;
            }
        }

        if (amount != 0) partyLedger.contributed += amount;
        
        ledgers[pIndex] = partyLedger;
    }

    function deposit(Party party) external payable {
        require(_validParty(msg.sender, party), "ERR-GA022 InvalidEnvironment");

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        uint256 pIndex = uint256(party);
        Ledger memory partyLedger = ledgers[pIndex];

        require(partyLedger.status != LedgerStatus.Finalized, "ERR-GA023 LedgerFinalized");
        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;

        partyLedger.balance += amount;
        
        ledgers[pIndex] = partyLedger;
    }

    // NOTE: DAPPs can gain malicious access to these funcs if they want to, but attacks beyond
    // the approved amounts will only lead to a revert.  
    // Bundlers must make sure the DApp hasn't maliciously upgraded their contract to avoid wasting gas. 
    function contributeTo(Party donor, Party recipient, uint256 amt) external {
        require(_validParties(msg.sender, donor, recipient), "ERR-GA021 InvalidEnvironment");
        _contributeTo(donor, recipient, amt);
    }

    function requestFrom(Party donor, Party recipient, uint256 amt) external {
        require(_validParties(msg.sender, donor, recipient), "ERR-GA022 InvalidEnvironment"); 
        _requestFrom(donor, recipient, amt);
    }

    function finalize(Party party, address partyAddress) external returns (bool) {
        require(_validParty(msg.sender, party), "ERR-GA024 InvalidEnvironment");
        require(party != Party.Solver, "ERR-GA025 SolverMustReconcile");

        uint256 pIndex = uint256(party);
        Ledger memory partyLedger = ledgers[pIndex];

        if (partyLedger.status == LedgerStatus.Finalized) return false;
        
        if (partyLedger.contributed + partyLedger.requested < 0) return false;

        uint256 grossBalance = uint256(_escrowAccountData[partyAddress].balance);

        if (int64(uint64(grossBalance / tx.gasprice)) + partyLedger.balance - 1 < 0) return false;
        
        partyLedger.status = LedgerStatus.Finalized;
        ledgers[pIndex] = partyLedger;

        return true;
    }

    function reconcile(address environment, address searcherFrom, uint256 maxApprovedGasSpend) external payable returns (bool) {
        // NOTE: approvedAmount is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe.  This will be subtracted later - tx will revert here if there isn't enough. 
        if (!_validParty(environment, Party.Solver)) {
            return false;
        }

        uint256 partyIndex = uint256(Party.Solver);

        Ledger memory partyLedger = ledgers[partyIndex];
        if (partyLedger.status == LedgerStatus.Finalized) {
            return false;
        }

        if (msg.value != 0) {
            int64 amount = int64(uint64((msg.value) / tx.gasprice));
            partyLedger.balance += amount;
        }

        if (maxApprovedGasSpend != 0) {
            uint256 solverSurplusBalance = uint256(_escrowAccountData[searcherFrom].balance) - (EscrowBits.SOLVER_GAS_LIMIT * tx.gasprice + 1);
            maxApprovedGasSpend = maxApprovedGasSpend > solverSurplusBalance ? solverSurplusBalance : maxApprovedGasSpend;
        

            int64 gasAllowance = int64(uint64(maxApprovedGasSpend / tx.gasprice));

            if (partyLedger.balance < 0) {
                if (gasAllowance < partyLedger.balance) {
                    return false;
                }
                gasAllowance += partyLedger.balance; // note that .balance is a negative number so this is a subtraction
            }

            partyLedger.contributed += gasAllowance; // note that surplus .contributed is refunded to the party
            partyLedger.balance -= gasAllowance;
        }

        if (partyLedger.contributed < 0) {
            return false;
        }
        
        partyLedger.status = LedgerStatus.Finalized; // no additional requests can be made to this party
        ledgers[partyIndex] = partyLedger;
        return true;
    }
}