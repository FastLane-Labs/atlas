//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {SafetyLocks} from "../atlas/SafetyLocks.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";


import {EscrowBits} from "../libraries/EscrowBits.sol";
import {PartyMath, LEDGER_LENGTH} from "../libraries/GasParties.sol";

import "forge-std/Test.sol";

abstract contract GasAccounting is SafetyLocks {
    using SafeTransferLib for ERC20;
    using PartyMath for Party;
    using PartyMath for uint256;
    using PartyMath for Ledger[LEDGER_LENGTH];

    mapping(address => EscrowAccountData) internal _escrowAccountData;

    constructor(address _simulator) SafetyLocks(_simulator) {}

    // NOTE: donations are simply deposits that have a different msg.sender than receiving party
    function _deposit(Party party, uint256 amt) internal returns (uint256 balanceOwed) {

        (Ledger memory pLedger, uint256 partyIndex) = _getLedger(party);

        require(pLedger.status != LedgerStatus.Finalized, "ERR-GA002, LedgerFinalized");

        int64 depositAmount = int64(uint64(amt / tx.gasprice));

        pLedger.balance += depositAmount;
        
        balanceOwed = pLedger.balance < 0 ? uint256(uint64(-1 * pLedger.balance)) : 0;

        ledgers[partyIndex] = pLedger;
    }


    function _borrow(Party party, uint256 amt) internal {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch. 
       
        (Ledger memory pLedger, uint256 partyIndex) = _getLedger(party);

        require(uint256(pLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA003a, LedgerFinalized");
       
        int64 borrowAmount = int64(uint64(amt / tx.gasprice))+1;
        pLedger.balance -= borrowAmount;
        pLedger.status = LedgerStatus.Borrowing;
        
        ledgers[partyIndex] = pLedger;
    }

    function _tradeCorrection(Party party, uint256 amt) internal {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch.
        // This function is to mark off a solver borrow from a failed tx 
       
        (Ledger memory pLedger, uint256 partyIndex) = _getLedger(party);

        require(pLedger.status == LedgerStatus.Borrowing, "ERR-GA003b, LedgerFinalized");
       
        int64 borrowAmount = int64(uint64(amt / tx.gasprice))+1;
        pLedger.balance += borrowAmount;
        pLedger.status = LedgerStatus.Active;
        
        ledgers[partyIndex] = pLedger;
    }

    function _use(Party party, address partyAddress, uint256 amt) internal {
        
        (Ledger memory pLedger, uint256 partyIndex) = _getLedger(party);

        require(uint256(pLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA004, LedgerBalancing");
        
        int64 amount = int64(uint64(amt / tx.gasprice))+1;

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

    function _requestFrom(Party donor, Party recipient, uint256 amt) internal {
        // TODO: different parties will be ineligible to request funds from once their phase is over.
        // We need to add a phase check to verify this. 

        (Ledger memory dLedger, uint256 donorIndex) = _getLedger(donor);
        require(uint256(dLedger.status) < uint256(LedgerStatus.Balancing), "ERR-GA004, LedgerBalancing");

        (Ledger memory rLedger, uint256 recipientIndex) = _getLedger(recipient);
        require(rLedger.status != LedgerStatus.Finalized, "ERR-GA005, LedgerFinalized");

        int64 amount = int64(uint64(amt / tx.gasprice));

        dLedger.contributed -= amount;
        rLedger.requested -= amount;

        ledgers[donorIndex] = dLedger;
        ledgers[recipientIndex] = rLedger;
    }

    function _contributeTo(Party donor, Party recipient, uint256 amt) internal {

        (Ledger memory dLedger, uint256 donorIndex) = _getLedger(donor);
        require(dLedger.status != LedgerStatus.Finalized, "ERR-GA006, LedgerFinalized");

        (Ledger memory rLedger, uint256 recipientIndex) = _getLedger(recipient);
        require(rLedger.status != LedgerStatus.Finalized, "ERR-GA007, LedgerFinalized");

        int64 amount = int64(uint64(amt / tx.gasprice));

        dLedger.balance -= amount;
        dLedger.contributed += amount;
        rLedger.requested += amount;

        ledgers[donorIndex] = dLedger;
        ledgers[recipientIndex] = rLedger;
    }


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

            Ledger memory pLedger = ledgers[i];
            if (uint256(pLedger.proxy) != i) {
                unchecked{++i;}
                continue;
            }

            totalBalanceDelta += pLedger.balance;
            totalRequests += pLedger.requested;
            totalContributions += pLedger.contributed;

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

        Ledger[LEDGER_LENGTH] memory mLedgers;

        (mLedgers, activeParties, totalRequests, totalContributions, totalBalanceDelta) = _loadLedgers(activeParties);

        (mLedgers, totalRequests, totalContributions, totalBalanceDelta) = _allocateGasRebate(
            mLedgers, mLock.startingBalance, accruedGasRebate, totalRequests, totalContributions, totalBalanceDelta);

        console.log("");
        console.log("* * * * * ");
        console.log("INITIAL:");
        _consolePrint(mLedgers, activeParties);
        console.log("_______");
        console.log("* * * * * ");
        console.log("");
        
        // First, remove overfilled requests (refunding to general pool)
        if (totalRequests > 0) {
            (mLedgers, totalRequests, totalContributions) = _removeSurplusRequests(
                mLedgers, activeParties, totalRequests, totalContributions);
        }

        // Next, balance each party's surplus contributions against their own deficit requests
        (mLedgers, totalRequests, totalContributions) = _balanceAgainstSelf(
            mLedgers, activeParties, totalRequests, totalContributions);

        // Then allocate surplus contributions back to the correct parties
        if (totalRequests + totalContributions > 0) {
            (mLedgers, totalRequests, totalContributions) = _allocateSurplusContributions(
                mLedgers, activeParties, totalRequests, totalContributions);
        }

        console.log("* * * * * ");
        console.log("FINAL:");
        _consolePrint(mLedgers, activeParties);
        console.log("_______");
        console.log("* * * * * ");

        // Finally, assign the balance deltas to the parties
        _assignBalanceDeltas(mLedgers, activeParties, user, dapp, winningSolver, bundler);
    }

    function _loadLedgers(uint256 activeParties) 
        internal
        view
        returns (Ledger[LEDGER_LENGTH] memory, uint256, int64, int64, int64) 
    {
        Ledger[LEDGER_LENGTH] memory mLedgers;

        int64 totalRequests;
        int64 totalContributions;
        int64 totalBalanceDelta;

        for (uint256 i; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }

            Ledger memory pLedger = ledgers[i];

            require(pLedger.contributed >= 0, "ERR-GA099 NoUnfilledRequests");

            // Only tally totals from non-proxies
            if (uint256(pLedger.proxy) == i) {
            
                totalBalanceDelta += pLedger.balance;
                totalRequests += pLedger.requested;
                totalContributions += pLedger.contributed;
            
            // Mark inactive if proxy
            } else {
                activeParties = activeParties.markInactive(Party(i));
            }

            mLedgers[i] = pLedger;

            unchecked{++i;}
        }

        return (mLedgers, activeParties, totalRequests, totalContributions, totalBalanceDelta);
    }

    function _allocateGasRebate(
        Ledger[LEDGER_LENGTH] memory mLedgers, uint64 startingGasBal,
        uint256 accruedGasRebate, int64 totalRequests, int64 totalContributions, int64 totalBalanceDelta) 
        internal 
        returns (Ledger[LEDGER_LENGTH] memory, int64, int64, int64)
    {
        int64 gasRemainder = int64(uint64(gasleft() + 20_000));

        // Reduce the bundler's gas request by the unused gas
        (, uint256 i) = mLedgers._getLedgerFromMemory(Party.Bundler);

        int64 gasRebate = int64(uint64(accruedGasRebate));

        mLedgers[i].requested += gasRemainder;
        mLedgers[i].balance += gasRebate;

        totalRequests += gasRemainder;
        totalContributions -= gasRemainder;
        totalBalanceDelta += gasRebate;

        require(totalRequests + totalContributions >= 0, "ERR-GA014a MissingFunds");

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
            revert("ERR-GA014b MissingFunds");
        }

        return (mLedgers, totalRequests, totalContributions, totalBalanceDelta);
    }
        
    function _balanceAgainstSelf(
        Ledger[LEDGER_LENGTH] memory mLedgers, uint256 activeParties, int64 totalRequests, int64 totalContributions) 
        internal 
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
    
            Ledger memory pLedger = mLedgers[i];
            
            // CASE: Some Requests still in Deficit
            if (pLedger.requested < 0 && pLedger.contributed > 0) {

                // CASE: Contributions > Requests
                if (pLedger.contributed + pLedger.requested > 0) {
                    totalRequests -= pLedger.requested; // subtracting a negative
                    totalContributions += pLedger.requested; // adding a negative

                    pLedger.contributed += pLedger.requested; // adding a negative
                    pLedger.requested = 0;
                
                // CASE: Requests >= Contributions
                } else {
                    totalRequests += pLedger.contributed; // adding a positive
                    totalContributions -= pLedger.contributed; // subtracting a positive

                    pLedger.requested += pLedger.contributed; // adding a positive
                    pLedger.contributed = 0;
                }

                mLedgers[i] = pLedger;
            }

        } while (i != 0);

        return (mLedgers, totalRequests, totalContributions);
    }

    function _removeSurplusRequests(
        Ledger[LEDGER_LENGTH] memory mLedgers, uint256 activeParties, int64 totalRequests, int64 totalContributions) 
        internal 
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
    
            Ledger memory pLedger = mLedgers[i];
            
            if (pLedger.requested > 0) {
                if (totalRequests > pLedger.requested) {
                    totalRequests -= pLedger.requested;
                    totalContributions += pLedger.requested;
                    pLedger.requested = 0;

                } else {
                    pLedger.requested -= totalRequests;
                    totalContributions += totalRequests;
                    totalRequests = 0;
                }

                mLedgers[i] = pLedger;
            }
            unchecked{++i;}
        } 

        return (mLedgers, totalRequests, totalContributions);
    }

    function _allocateSurplusContributions(
        Ledger[LEDGER_LENGTH] memory mLedgers, uint256 activeParties, int64 totalRequests, int64 totalContributions) 
        internal 
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
    
            Ledger memory pLedger = mLedgers[i];
            
            if (pLedger.contributed > 0) {
                if (netBalance > pLedger.contributed) {
                    totalContributions -= pLedger.contributed;
                    pLedger.balance += pLedger.contributed;
                    pLedger.contributed = 0;

                } else {
                    pLedger.contributed -= netBalance;
                    pLedger.balance += netBalance;
                    totalContributions -= netBalance;
                }

                mLedgers[i] = pLedger;

                netBalance = totalRequests + totalContributions;
            }

        } while (i != 0 && netBalance > 0);

        return (mLedgers, totalRequests, totalContributions);
    }

    function _assignBalanceDeltas(
        Ledger[LEDGER_LENGTH] memory mLedgers, 
        uint256 activeParties, address user, address dapp, address winningSolver, address bundler) 
        internal 
    {
        for (uint256 i=0; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked{++i;}
                continue;
            }

            Ledger memory pLedger = mLedgers[i];

            address partyAddress = _partyAddress(i, user, dapp, winningSolver, bundler);
            EscrowAccountData memory escrowData = _escrowAccountData[partyAddress];


            console.log("-");
            console.log("Starting Bal:", escrowData.balance);

            
            bool requiresUpdate;
            if (pLedger.balance < 0) {
                escrowData.balance -= (uint128(uint64(pLedger.balance * -1)) * uint128(tx.gasprice));
                requiresUpdate = true;
            
            } else if (pLedger.balance > 0) {
                escrowData.balance += (uint128(uint64(pLedger.balance)) * uint128(tx.gasprice));
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

    function _consolePrint(Ledger[LEDGER_LENGTH] memory mLedgers, uint256 activeParties) internal view {
        for (uint256 i=0; i < LEDGER_LENGTH; i++) {
            if (activeParties.isInactive(i)) {
                console.log("");
                console.log("Party:", _partyName(i));
                console.log("confirmed - inactive");
                console.log("-");
                continue;
            }
    
            Ledger memory pLedger = mLedgers[i];

            if (pLedger.status == LedgerStatus.Proxy) {
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
            _logInt64("netBalance  :", pLedger.balance);
            _logInt64("requested   :", pLedger.requested);
            _logInt64("contributed :", pLedger.contributed);
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

    function _getLedger(Party party) internal view returns (Ledger memory pLedger, uint256 index) {
        uint256 partyIndex;

        do {
            partyIndex = uint256(party);
            pLedger = ledgers[partyIndex];
            party = pLedger.proxy;
            index = uint256(party);
            
        } while (partyIndex != index);

        if (pLedger.status == LedgerStatus.Inactive) pLedger.status = LedgerStatus.Active;
    }

    function _checkSolverProxy(address solverFrom, address bundler) internal returns (bool validSolver) {
        // Note that the Solver can't be the User or the DApp - those combinations are blocked in the ExecutionEnvironment. 

        if (solverFrom == block.coinbase) {
            uint256 builderIndex = uint256(Party.Builder);
            Ledger memory pLedger = ledgers[builderIndex];

            // CASE: Invalid combination (solver = coinbase = user | dapp)
            if (uint256(pLedger.proxy) > uint256(Party.Solver)) {
                console.log("inv-a");
                return false;
            }

            // CASE: ledger is finalized or balancing
            if (uint256(pLedger.status) > uint256(LedgerStatus.Borrowing)) {
                console.log("inv-b");
                return false;
            }

            // CASE: proxy is solver or builder
            // Pass, and check builder proxy next

            // CASE: no proxy yet, so make one
            if (uint256(pLedger.proxy) == builderIndex) {
                uint256 activeParties = _getActiveParties();
                if (activeParties.isInactive(Party.Builder)) {
                    _saveActiveParties(activeParties.markActive(Party.Builder));
                }

                pLedger.status = LedgerStatus.Proxy;
                pLedger.proxy = Party.Solver;
                // Note: don't overwrite the stored values - we may need to undo the proxy if solver fails
                ledgers[builderIndex] = pLedger; 

                // Solver inherits the requests and contributions of their alter ego
                uint256 solverIndex = uint256(Party.Solver);
                Ledger memory sLedger = ledgers[solverIndex];

                sLedger.balance += pLedger.balance;
                sLedger.contributed += pLedger.contributed;
                sLedger.requested += pLedger.requested;

                ledgers[solverIndex] = sLedger;
            }
        } 
        

        if (solverFrom == bundler) {
            uint256 bundlerIndex = uint256(Party.Bundler);
            Ledger memory pLedger = ledgers[bundlerIndex];

            // CASE: Invalid combination (solver = bundler = user | dapp)
            if (uint256(pLedger.proxy) > uint256(Party.Solver)) {
                console.log("inv-c");
                return false;
            }

            // CASE: ledger is finalized or balancing
            if (uint256(pLedger.status) > uint256(LedgerStatus.Borrowing)) {
                console.log("inv-d");
                return false;
            }

            // CASE: proxy is solver or builder
            // Pass, and check builder proxy next

            // CASE: no proxy
            if (uint256(pLedger.proxy) == bundlerIndex) {
                // Bundler is always active, so no need to mark. 

                pLedger.status = LedgerStatus.Proxy;
                pLedger.proxy = Party.Solver;
                // Note: don't overwrite the stored values - we may need to undo the proxy if solver fails
                ledgers[bundlerIndex] = pLedger; 

                // Solver inherits the requests and contributions of their alter ego
                uint256 solverIndex = uint256(Party.Solver);
                Ledger memory sLedger = ledgers[solverIndex];

                sLedger.balance += pLedger.balance;
                sLedger.contributed += pLedger.contributed;
                sLedger.requested += pLedger.requested;

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
            Ledger memory pLedger = ledgers[builderIndex];
            Ledger memory sLedger = ledgers[solverIndex];
            
            if (solverSuccessful) {
            // CASE: Delete the balances on the older ledger
            // TODO: Pretty sure we can skip this since it gets ignored and deleted later
                pLedger.balance = 0;
                pLedger.contributed = 0;
                pLedger.requested = 0;

                ledgers[builderIndex] = pLedger; // Proxy status stays
                
            } else {
            // CASE: Undo the balance adjustments for the next solver
                sLedger.balance -= pLedger.balance;
                sLedger.contributed -= pLedger.contributed;
                sLedger.requested -= pLedger.requested;

                ledgers[solverIndex] = sLedger;

                pLedger.proxy = Party.Builder;
                pLedger.status = LedgerStatus.Active;

                ledgers[builderIndex] = pLedger;
            }
        }

        if (solverFrom == bundler) {
           
            uint256 bundlerIndex = uint256(Party.Bundler);
            uint256 solverIndex = uint256(Party.Solver);

            // Solver inherited the requests and contributions of their alter ego
            Ledger memory pLedger = ledgers[bundlerIndex];
            Ledger memory sLedger = ledgers[solverIndex];
            
            if (solverSuccessful) {
            // CASE: Delete the balances on the older ledger
            // TODO: Pretty sure we can skip this since it gets ignored and deleted later
                pLedger.balance = 0;
                pLedger.contributed = 0;
                pLedger.requested = 0;

                ledgers[bundlerIndex] = pLedger; // Proxy status stays
                
            } else {
            // CASE: Undo the balance adjustments for the next solver
                sLedger.balance -= pLedger.balance;
                sLedger.contributed -= pLedger.contributed;
                sLedger.requested -= pLedger.requested;

                ledgers[solverIndex] = sLedger;

                pLedger.proxy = Party.Bundler;
                pLedger.status = LedgerStatus.Active;
                
                ledgers[bundlerIndex] = pLedger;
            }
        }
    }

    function contribute(Party recipient) external payable {
        require(_validParty(msg.sender, recipient), "ERR-GA020 InvalidEnvironment"); 

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        (Ledger memory pLedger, uint256 pIndex) = _getLedger(recipient);

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

    function deposit(Party party) external payable {
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
        if (!_validParty(environment, Party.Solver)) {
            return false;
        }

        uint256 partyIndex = uint256(Party.Solver);

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