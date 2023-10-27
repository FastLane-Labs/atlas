//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafetyLocks} from "../atlas/SafetyLocks.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";


import {EscrowBits} from "../libraries/EscrowBits.sol";
import {PartyMath, LEDGER_LENGTH} from "../libraries/GasParties.sol";

import "forge-std/Test.sol";

abstract contract GasAccounting is SafetyLocks {
    using PartyMath for Party;
    using PartyMath for uint256;
    using PartyMath for Ledger[LEDGER_LENGTH];

    mapping(address => EscrowAccountData) internal _escrowAccountData;

    constructor(address _simulator) SafetyLocks(_simulator) {}

    // NOTE: donations are simply deposits that have a different msg.sender than receiving party
    function _deposit(Party party, uint256 amt) internal returns (uint256 balanceOwed) {

        (Ledger memory partyLedger, uint256 partyIndex) = _getLedger(party);

        if (partyLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(1);

        int64 depositAmount = int64(uint64(amt / tx.gasprice));

        partyLedger.balance += depositAmount;
        
        balanceOwed = partyLedger.balance < 0 ? uint256(uint64(-1 * partyLedger.balance)) : 0;

        ledgers[partyIndex] = partyLedger;
    }


    function _borrow(Party party, uint256 amt) internal {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch. 
       
        (Ledger memory partyLedger, uint256 partyIndex) = _getLedger(party);

        if(partyLedger.status >= LedgerStatus.Borrowing) revert LedgerFinalized(2);
       
        int64 borrowAmount = int64(uint64(amt / tx.gasprice))+1;
        partyLedger.balance -= borrowAmount;
        partyLedger.status = LedgerStatus.Borrowing;
        
        ledgers[partyIndex] = partyLedger;
    }

    function _tradeCorrection(Party party, uint256 amt) internal {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch.
        // This function is to mark off a solver borrow from a failed tx 
       
        (Ledger memory partyLedger, uint256 partyIndex) = _getLedger(party);

        if(partyLedger.status != LedgerStatus.Borrowing) revert LedgerFinalized(3);

        int64 borrowAmount = int64(uint64(amt / tx.gasprice))+1;
        partyLedger.balance += borrowAmount;
        partyLedger.status = LedgerStatus.Active;
        
        ledgers[partyIndex] = partyLedger;
    }

    function _use(Party party, address partyAddress, uint256 amt) internal {
        
        (Ledger memory partyLedger, uint256 partyIndex) = _getLedger(party);

        if(partyLedger.status >= LedgerStatus.Balancing) revert LedgerBalancing(1);
        
        int64 amount = int64(uint64(amt / tx.gasprice))+1;

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

        revert InsufficientFunds();
    }

    function _requestFrom(Party donor, Party recipient, uint256 amt) internal {
        // TODO: different parties will be ineligible to request funds from once their phase is over.
        // We need to add a phase check to verify this. 

        (Ledger memory donorLedger, uint256 donorIndex) = _getLedger(donor);
        if(donorLedger.status >= LedgerStatus.Balancing) revert LedgerBalancing(2);

        (Ledger memory recipientLedger, uint256 recipientIndex) = _getLedger(recipient);
        if(recipientLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(4);

        int64 amount = int64(uint64(amt / tx.gasprice));

        donorLedger.contributed -= amount;
        recipientLedger.requested -= amount;

        ledgers[donorIndex] = donorLedger;
        ledgers[recipientIndex] = recipientLedger;
    }

    function _contributeTo(Party donor, Party recipient, uint256 amt) internal {

        (Ledger memory donorLedger, uint256 donorIndex) = _getLedger(donor);
        if(donorLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(5);

        (Ledger memory recipientLedger, uint256 recipientIndex) = _getLedger(recipient);
        if(recipientLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(6);

        int64 amount = int64(uint64(amt / tx.gasprice));

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

        int64 totalBalanceDelta;
        int64 totalRequests;
        int64 totalContributions;

        uint256 activeParties = uint256(mLock.activeParties);
        for (uint256 i; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties & 1<<(i+1) == 0){
                unchecked{++i;}
                continue;
            }

            Ledger memory partyLedger = ledgers[i];
            if (uint256(partyLedger.proxy) != i) {
                unchecked{++i;}
                continue;
            }

            totalBalanceDelta += partyLedger.balance;
            totalRequests += partyLedger.requested;
            totalContributions += partyLedger.contributed;

            unchecked{++i;}
        }

        int64 atlasBalanceDelta = int64(uint64((address(this).balance) / tx.gasprice)) - int64(mLock.startingBalance);

        // If atlas balance is lower than expected, return false
        if (atlasBalanceDelta < totalRequests + totalContributions + totalBalanceDelta) return false;

        // If the requests have not yet been met, return false
        if (totalRequests + totalContributions < 0) return false;

        // Otherwise return true
        return true;
    }

    function _balance(uint256 accruedGasRebate, address user, address dapp, address winningSolver, address bundler) internal {
        
        Lock memory mLock = lock;
        uint256 activeParties = uint256(mLock.activeParties);

        int64 totalRequests;
        int64 totalContributions;
        int64 totalBalanceDelta;

        Ledger[LEDGER_LENGTH] memory parties;

        (parties, activeParties, totalRequests, totalContributions, totalBalanceDelta) = _loadLedgers(activeParties);

        (parties, totalRequests, totalContributions, totalBalanceDelta) = _allocateGasRebate(
            parties, mLock.startingBalance, accruedGasRebate, totalRequests, totalContributions, totalBalanceDelta);

        console.log("");
        console.log("* * * * * ");
        console.log("INITIAL:");
        _consolePrint(parties, activeParties);
        console.log("_______");
        console.log("* * * * * ");
        console.log("");
        
        // First, remove overfilled requests (refunding to general pool)
        if (totalRequests > 0) {
            (parties, totalRequests, totalContributions) = _removeSurplusRequests(
                parties, activeParties, totalRequests, totalContributions);
        }

        // Next, balance each party's surplus contributions against their own deficit requests
        (parties, totalRequests, totalContributions) = _balanceAgainstSelf(
            parties, activeParties, totalRequests, totalContributions);

        // Then allocate surplus contributions back to the correct parties
        if (totalRequests + totalContributions > 0) {
            (parties, totalRequests, totalContributions) = _allocateSurplusContributions(
                parties, activeParties, totalRequests, totalContributions);
        }

        console.log("* * * * * ");
        console.log("FINAL:");
        _consolePrint(parties, activeParties);
        console.log("_______");
        console.log("* * * * * ");

        // Finally, assign the balance deltas to the parties
        _assignBalanceDeltas(parties, activeParties, user, dapp, winningSolver, bundler);
    }

    function _loadLedgers(uint256 activeParties) 
        internal
        view
        returns (Ledger[LEDGER_LENGTH] memory, uint256, int64, int64, int64) 
    {
        Ledger[LEDGER_LENGTH] memory parties;

        int64 totalRequests;
        int64 totalContributions;
        int64 totalBalanceDelta;

        for (uint256 i; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }

            Ledger memory partyLedger = ledgers[i];

            if(partyLedger.contributed < 0) revert NoUnfilledRequests();

            // Only tally totals from non-proxies
            if (uint256(partyLedger.proxy) == i) {
            
                totalBalanceDelta += partyLedger.balance;
                totalRequests += partyLedger.requested;
                totalContributions += partyLedger.contributed;
            
            // Mark inactive if proxy
            } else {
                activeParties = activeParties.markInactive(Party(i));
            }

            parties[i] = partyLedger;

            unchecked{++i;}
        }

        return (parties, activeParties, totalRequests, totalContributions, totalBalanceDelta);
    }

    function _allocateGasRebate(
        Ledger[LEDGER_LENGTH] memory parties, uint64 startingGasBal,
        uint256 accruedGasRebate, int64 totalRequests, int64 totalContributions, int64 totalBalanceDelta) 
        internal
        view
        returns (Ledger[LEDGER_LENGTH] memory, int64, int64, int64)
    {
        int64 gasRemainder = int64(uint64(gasleft() + 20_000));

        // Reduce the bundler's gas request by the unused gas
        (, uint256 i) = parties._getLedgerFromMemory(Party.Bundler);

        int64 gasRebate = int64(uint64(accruedGasRebate));

        parties[i].requested += gasRemainder;
        parties[i].balance += gasRebate;

        totalRequests += gasRemainder;
        totalContributions -= gasRemainder;
        totalBalanceDelta += gasRebate;

        if(totalRequests + totalContributions < 0) revert MissingFunds(1);

        // TODO: Adjust to accomodate the direction of rounding errors. 
        int64 atlasBalanceDelta = int64(uint64(address(this).balance / tx.gasprice)) - int64(startingGasBal);

        {
            console.log("");
            console.log("--");
            _logInt64("gasRemainder :", gasRemainder);
            console.log("gasRebate    : +", accruedGasRebate);
            console.log("-");
            _logInt64("observedDelta:", atlasBalanceDelta);
            _logInt64("actualDelta  :", totalBalanceDelta);
            console.log("-");
            _logInt64("surplus      :", totalRequests + totalContributions);
            _logInt64("totalRequests:", totalRequests);
            _logInt64("contributions:", totalContributions);
            console.log("--");
        }

        if (atlasBalanceDelta < totalBalanceDelta + totalContributions + totalRequests) {            
            revert MissingFunds(2);
        }

        return (parties, totalRequests, totalContributions, totalBalanceDelta);
    }
        
    function _balanceAgainstSelf(
        Ledger[LEDGER_LENGTH] memory parties, uint256 activeParties, int64 totalRequests, int64 totalContributions) 
        internal 
        pure
        returns (Ledger[LEDGER_LENGTH] memory, int64, int64) 
    {
        // NOTE:
        // ORDER is:
        // 1:  FirstToAct (DApp) 
        // ...
        // Last: LastToAct (builder)

        uint256 i = LEDGER_LENGTH;

        do {
            --i;

            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                continue;
            }
    
            Ledger memory partyLedger = parties[i];
            
            // CASE: Some Requests still in Deficit
            if (partyLedger.requested < 0 && partyLedger.contributed > 0) {

                // CASE: Contributions > Requests
                if (partyLedger.contributed + partyLedger.requested > 0) {
                    totalRequests -= partyLedger.requested; // subtracting a negative
                    totalContributions += partyLedger.requested; // adding a negative

                    partyLedger.contributed += partyLedger.requested; // adding a negative
                    partyLedger.requested = 0;
                
                // CASE: Requests >= Contributions
                } else {
                    totalRequests += partyLedger.contributed; // adding a positive
                    totalContributions -= partyLedger.contributed; // subtracting a positive

                    partyLedger.requested += partyLedger.contributed; // adding a positive
                    partyLedger.contributed = 0;
                }

                parties[i] = partyLedger;
            }

        } while (i != 0);

        return (parties, totalRequests, totalContributions);
    }

    function _removeSurplusRequests(
        Ledger[LEDGER_LENGTH] memory parties, uint256 activeParties, int64 totalRequests, int64 totalContributions) 
        internal 
        pure
        returns (Ledger[LEDGER_LENGTH] memory, int64, int64) 
    {
        // NOTE: A check to verify totalRequests > 0 will happen prior to calling this

        // NOTE:
        // ORDER is:
        // 1: LastToAct (builder)
        // ...
        // Last: FirstToAct (DApp)

        for (uint256 i; i <LEDGER_LENGTH && totalRequests > 0; ) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }
    
            Ledger memory partyLedger = parties[i];
            
            if (partyLedger.requested > 0) {
                if (totalRequests > partyLedger.requested) {
                    totalRequests -= partyLedger.requested;
                    totalContributions += partyLedger.requested;
                    partyLedger.requested = 0;

                } else {
                    partyLedger.requested -= totalRequests;
                    totalContributions += totalRequests;
                    totalRequests = 0;
                }

                parties[i] = partyLedger;
            }
            unchecked{++i;}
        } 

        return (parties, totalRequests, totalContributions);
    }

    function _allocateSurplusContributions(
        Ledger[LEDGER_LENGTH] memory parties, uint256 activeParties, int64 totalRequests, int64 totalContributions) 
        internal 
        pure
        returns (Ledger[LEDGER_LENGTH] memory, int64, int64) 
    {
        // NOTE: A check to verify totalRequests + totalContributions > 0 will happen prior to calling this
        
        // NOTE:
        // ORDER is:
        // 1:  FirstToAct (DApp) 
        // ...
        // Last: LastToAct (builder)

        int64 netBalance = totalRequests + totalContributions;
        
        uint256 i = LEDGER_LENGTH;

        do {
            --i;

            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                continue;
            }
    
            Ledger memory partyLedger = parties[i];
            
            if (partyLedger.contributed > 0) {
                if (netBalance > partyLedger.contributed) {
                    totalContributions -= partyLedger.contributed;
                    partyLedger.balance += partyLedger.contributed;
                    partyLedger.contributed = 0;

                } else {
                    partyLedger.contributed -= netBalance;
                    partyLedger.balance += netBalance;
                    totalContributions -= netBalance;
                }

                parties[i] = partyLedger;

                netBalance = totalRequests + totalContributions;
            }

        } while (i != 0 && netBalance > 0);

        return (parties, totalRequests, totalContributions);
    }

    function _assignBalanceDeltas(
        Ledger[LEDGER_LENGTH] memory parties, 
        uint256 activeParties, address user, address dapp, address winningSolver, address bundler) 
        internal 
    {
        for (uint256 i=0; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }

            Ledger memory partyLedger = parties[i];

            address partyAddress = _partyAddress(i, user, dapp, winningSolver, bundler);
            EscrowAccountData memory escrowData = _escrowAccountData[partyAddress];


            console.log("-");
            console.log("Starting Bal:", escrowData.balance);

            
            bool requiresUpdate;
            if (partyLedger.balance < 0) {
                escrowData.balance -= (uint128(uint64(partyLedger.balance * -1)) * uint128(tx.gasprice));
                requiresUpdate = true;
            
            } else if (partyLedger.balance > 0) {
                escrowData.balance += (uint128(uint64(partyLedger.balance)) * uint128(tx.gasprice));
                requiresUpdate = true;
            }

            if (i == uint256(Party.Solver)) {
                ++escrowData.nonce;
                requiresUpdate = true;
            }

            // Track lastAccessed for all parties, although only check against it for solver parties
            if (requiresUpdate) {
                escrowData.lastAccessed = uint64(block.number);
                _escrowAccountData[partyAddress] = escrowData;
            }
            
            console.log("Ending Bal  :", escrowData.balance);
            console.log("-");
            

            unchecked{++i;}
        }
    }

    function _consolePrint(Ledger[LEDGER_LENGTH] memory parties, uint256 activeParties) internal view {
        for (uint256 i=0; i < LEDGER_LENGTH; i++) {
            if (activeParties.isInactive(i)) {
                console.log("");
                console.log("Party:", _partyName(i));
                console.log("confirmed - inactive");
                console.log("-");
                continue;
            }
    
            Ledger memory partyLedger = parties[i];

            if (partyLedger.status == LedgerStatus.Proxy) {
                console.log("");
                console.log("Party:", _partyName(i));
                console.log("confirmed - proxy");
                console.log("-");
                continue;
            }

            console.log("");
            console.log("Party:", _partyName(i));
            console.log("confirmed - ACTIVE");
            console.log("-");          
            _logInt64("netBalance  :", partyLedger.balance);
            _logInt64("requested   :", partyLedger.requested);
            _logInt64("contributed :", partyLedger.contributed);
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

    function _getLedger(Party party) internal view returns (Ledger memory partyLedger, uint256 index) {
        uint256 partyIndex;

        do {
            partyIndex = uint256(party);
            partyLedger = ledgers[partyIndex];
            party = partyLedger.proxy;
            index = uint256(party);
            
        } while (partyIndex != index);

        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;
    }

    function _checkSolverProxy(address solverFrom, address bundler) internal returns (bool validSolver) {
        // Note that the Solver can't be the User or the DApp - those combinations are blocked in the ExecutionEnvironment. 

        if (solverFrom == block.coinbase) {
            uint256 builderIndex = uint256(Party.Builder);
            Ledger memory partyLedger = ledgers[builderIndex];

            // CASE: Invalid combination (solver = coinbase = user | dapp)
            if (uint256(partyLedger.proxy) > uint256(Party.Solver)) {
                return false;
            }

            // CASE: ledger is finalized or balancing
            if (uint256(partyLedger.status) > uint256(LedgerStatus.Borrowing)) {
                return false;
            }

            // CASE: proxy is solver or builder
            // Pass, and check builder proxy next

            // CASE: no proxy yet, so make one
            if (uint256(partyLedger.proxy) == builderIndex) {
                uint256 activeParties = _getActiveParties();
                if (activeParties.isInactive(Party.Builder)) {
                    _saveActiveParties(activeParties.markActive(Party.Builder));
                }

                partyLedger.status = LedgerStatus.Proxy;
                partyLedger.proxy = Party.Solver;
                // Note: don't overwrite the stored values - we may need to undo the proxy if solver fails
                ledgers[builderIndex] = partyLedger; 

                // Solver inherits the requests and contributions of their alter ego
                uint256 solverIndex = uint256(Party.Solver);
                Ledger memory sLedger = ledgers[solverIndex];

                sLedger.balance += partyLedger.balance;
                sLedger.contributed += partyLedger.contributed;
                sLedger.requested += partyLedger.requested;

                ledgers[solverIndex] = sLedger;
            }
        } 
        

        if (solverFrom == bundler) {
            uint256 bundlerIndex = uint256(Party.Bundler);
            Ledger memory partyLedger = ledgers[bundlerIndex];

            // CASE: Invalid combination (solver = bundler = user | dapp)
            if (uint256(partyLedger.proxy) > uint256(Party.Solver)) {
                return false;
            }

            // CASE: ledger is finalized or balancing
            if (uint256(partyLedger.status) > uint256(LedgerStatus.Borrowing)) {
                return false;
            }

            // CASE: proxy is solver or builder
            // Pass, and check builder proxy next

            // CASE: no proxy
            if (uint256(partyLedger.proxy) == bundlerIndex) {
                // Bundler is always active, so no need to mark. 

                partyLedger.status = LedgerStatus.Proxy;
                partyLedger.proxy = Party.Solver;
                // Note: don't overwrite the stored values - we may need to undo the proxy if solver fails
                ledgers[bundlerIndex] = partyLedger; 

                // Solver inherits the requests and contributions of their alter ego
                uint256 solverIndex = uint256(Party.Solver);
                Ledger memory sLedger = ledgers[solverIndex];

                sLedger.balance += partyLedger.balance;
                sLedger.contributed += partyLedger.contributed;
                sLedger.requested += partyLedger.requested;

                ledgers[solverIndex] = sLedger;
            }
        }
   
        return true;
    }

    function _updateSolverProxy(address solverFrom, address bundler, bool solverSuccessful) internal {
        // Note that the Solver can't be the User or the DApp - those combinations are blocked in the ExecutionEnvironment. 
        
        if (solverFrom == block.coinbase && block.coinbase != bundler) {

            uint256 builderIndex = uint256(Party.Builder);
            uint256 solverIndex = uint256(Party.Solver);

            // Solver inherited the requests and contributions of their alter ego
            Ledger memory partyLedger = ledgers[builderIndex];
            Ledger memory sLedger = ledgers[solverIndex];
            
            if (solverSuccessful) {
            // CASE: Delete the balances on the older ledger
            // TODO: Pretty sure we can skip this since it gets ignored and deleted later
                partyLedger.balance = 0;
                partyLedger.contributed = 0;
                partyLedger.requested = 0;

                ledgers[builderIndex] = partyLedger; // Proxy status stays
                
            } else {
            // CASE: Undo the balance adjustments for the next solver
                sLedger.balance -= partyLedger.balance;
                sLedger.contributed -= partyLedger.contributed;
                sLedger.requested -= partyLedger.requested;

                ledgers[solverIndex] = sLedger;

                partyLedger.proxy = Party.Builder;
                partyLedger.status = LedgerStatus.Active;

                ledgers[builderIndex] = partyLedger;
            }
        }

        if (solverFrom == bundler) {
           
            uint256 bundlerIndex = uint256(Party.Bundler);
            uint256 solverIndex = uint256(Party.Solver);

            // Solver inherited the requests and contributions of their alter ego
            Ledger memory partyLedger = ledgers[bundlerIndex];
            Ledger memory sLedger = ledgers[solverIndex];
            
            if (solverSuccessful) {
            // CASE: Delete the balances on the older ledger
            // TODO: Pretty sure we can skip this since it gets ignored and deleted later
                partyLedger.balance = 0;
                partyLedger.contributed = 0;
                partyLedger.requested = 0;

                ledgers[bundlerIndex] = partyLedger; // Proxy status stays
                
            } else {
            // CASE: Undo the balance adjustments for the next solver
                sLedger.balance -= partyLedger.balance;
                sLedger.contributed -= partyLedger.contributed;
                sLedger.requested -= partyLedger.requested;

                ledgers[solverIndex] = sLedger;

                partyLedger.proxy = Party.Bundler;
                partyLedger.status = LedgerStatus.Active;
                
                ledgers[bundlerIndex] = partyLedger;
            }
        }
    }

    function contribute(Party recipient) external payable {
        if(!_validParty(msg.sender, recipient)) revert InvalidEnvironment();

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        (Ledger memory partyLedger, uint256 pIndex) = _getLedger(recipient);

        if(partyLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(7);

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
        if(!_validParty(msg.sender, party)) revert InvalidEnvironment();

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        uint256 pIndex = uint256(party);
        Ledger memory partyLedger = ledgers[pIndex];

        if(partyLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(8);

        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;

        partyLedger.balance += amount;
        
        ledgers[pIndex] = partyLedger;
    }

    // NOTE: DAPPs can gain malicious access to these funcs if they want to, but attacks beyond
    // the approved amounts will only lead to a revert.  
    // Bundlers must make sure the DApp hasn't maliciously upgraded their contract to avoid wasting gas. 
    function contributeTo(Party donor, Party recipient, uint256 amt) external {
        if(!_validParties(msg.sender, donor, recipient)) revert InvalidEnvironment();
        _contributeTo(donor, recipient, amt);
    }

    function requestFrom(Party donor, Party recipient, uint256 amt) external {
        if(!_validParties(msg.sender, donor, recipient)) revert InvalidEnvironment();
        _requestFrom(donor, recipient, amt);
    }

    function finalize(Party party, address partyAddress) external returns (bool) {
        if(!_validParty(msg.sender, party)) revert InvalidEnvironment();
        if(party == Party.Solver) revert SolverMustReconcile();

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