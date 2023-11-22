//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { PartyMath } from "../libraries/GasParties.sol";
import { EscrowBits } from "../libraries/EscrowBits.sol";
import { Storage } from "./Storage.sol";
import { FastLaneErrorsEvents } from "../types/Emissions.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";
import "../types/SolverCallTypes.sol";

import "forge-std/Test.sol"; //TODO remove

// TODO check for address(this) or other assumptions from when inside Atlas inheritance

contract GasAccountingLib is Storage, FastLaneErrorsEvents {
    using PartyMath for Party;
    using PartyMath for uint256;
    using PartyMath for Ledger[LEDGER_LENGTH];

    address public immutable ATLAS;

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        // address _gasAccLib,
        address _safetyLocksLib,
        address _simulator,
        address _atlas
    )
        Storage(_escrowDuration, _factory, _verification, address(this), _safetyLocksLib, _simulator)
    {
        ATLAS = _atlas;
    }

    // ---------------------------------------
    //            EXTERNAL FUNCTIONS
    // ---------------------------------------

    function deposit(Party party) external payable {
        if (!_validParty(msg.sender, party)) revert InvalidEnvironment();

        int64 amount = int64(uint64((msg.value) / tx.gasprice));

        address partyAddress = parties[uint256(party)];

        Ledger memory partyLedger = ledgers[partyAddress];

        if (partyLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(8);

        if (partyLedger.status == LedgerStatus.Inactive) partyLedger.status = LedgerStatus.Active;

        partyLedger.balance += amount;

        ledgers[partyAddress] = partyLedger;
    }

    function setSolverLedger(address solverFrom, uint256 solverOpValue) external {
        // Note that for Solver borrows, the repayment check happens *inside* the try/catch.

        // Check to make sure the solverFrom doesnt already have an active ledger
        Ledger memory solverLedger = ledgers[solverFrom];

        if (solverLedger.status >= LedgerStatus.Borrowing) revert LedgerFinalized(2);

        // Load the solver proxy ledger and add it to the accounting
        Ledger memory proxyLedger = ledgers[SOLVER_PROXY];

        if (solverLedger.status == LedgerStatus.Inactive) {
            solverLedger = proxyLedger;
        } else {
            solverLedger.balance += proxyLedger.balance;
            solverLedger.contributed += proxyLedger.contributed;
            solverLedger.requested += proxyLedger.requested;
        }

        if (solverOpValue != 0) {
            int64 borrowAmount = int64(uint64(solverOpValue / tx.gasprice)) + 1;
            solverLedger.balance -= borrowAmount;
            solverLedger.status = LedgerStatus.Borrowing;
        }

        ledgers[solverFrom] = solverLedger;

        parties[uint256(Party.Solver)] = solverFrom;
    }

    function releaseSolverLedger(SolverOperation calldata solverOp, uint256 gasWaterMark, uint256 result) external {
        // parties[uint256(Party.Solver)] = SOLVER_PROXY; // unnecessary

        address solverFrom = solverOp.from;

        delete ledgers[solverFrom];

        // Calculate what the solver owes
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        uint256 solverBalance = (balanceOf[solverFrom] / tx.gasprice) - 1;

        uint256 gasUsed = gasWaterMark - gasleft() + 5_000;
        if (result & EscrowBits._FULL_REFUND != 0) {
            gasUsed = gasUsed + (solverOp.data.length * CALLDATA_LENGTH_PREMIUM) + 1;
        } else if (result & EscrowBits._CALLDATA_REFUND != 0) {
            gasUsed = (solverOp.data.length * CALLDATA_LENGTH_PREMIUM) + 1;
        } else if (result & EscrowBits._NO_USER_REFUND != 0) {
            return;
        } else {
            revert UncoveredResult();
        }

        gasUsed = gasUsed > solverBalance ? solverBalance : gasUsed;

        balanceOf[solverFrom] -= (gasUsed * tx.gasprice);

        address bundler = parties[uint256(Party.Bundler)];
        Ledger memory bundlerLedger = ledgers[bundler];

        bundlerLedger.balance += gasUsed;
        bundlerLedger.requested += gasUsed;  

        ledgers[bundler] = bundlerLedger;         
    }

    // NOTE: DAPPs can gain malicious access to these funcs if they want to, but attacks beyond
    // the approved amounts will only lead to a revert.
    // Bundlers must make sure the DApp hasn't maliciously upgraded their contract to avoid wasting gas.

    // callingEnv should be either internal Atlas call (from Permit69) or from an ExecEnv via Atlas to this contract
    function contributeTo(address callingEnv, Party donor, Party recipient, uint256 amt) external payable {
        if (!_validParties(callingEnv, donor, recipient)) revert InvalidEnvironment();
        
        address donorAddress = parties[uint256(donor)];
        Ledger memory donorLedger = ledgers[donorAddress];
        if (donorLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(5);

        address recipientAddress = parties[uint256(recipient)];
        Ledger memory recipientLedger = ledgers[recipientAddress];
        if (recipientLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(6);

        int64 amount = int64(uint64(amt / tx.gasprice));

        donorLedger.balance -= amount;

        if (msg.value != 0) {
            amount += int64(uint64(msg.value / tx.gasprice));
        }

        donorLedger.contributed += amount;
        recipientLedger.requested += amount;

        ledgers[donorAddress] = donorLedger;
        ledgers[recipientAddress] = recipientLedger;
    }

    // callingEnv should be either internal Atlas call (from Permit69) or from an ExecEnv via Atlas to this contract
    function requestFrom(address callingEnv, Party donor, Party recipient, uint256 amt) external {
        if (!_validParties(callingEnv, donor, recipient)) revert InvalidEnvironment();

        address donorAddress = parties[uint256(donor)];
        Ledger memory donorLedger = ledgers[donorAddress];
        if (donorLedger.status >= LedgerStatus.Balancing) revert LedgerBalancing(2);

        address recipientAddress = parties[uint256(recipient)];
        Ledger memory recipientLedger = ledgers[recipientAddress];
        if (recipientLedger.status == LedgerStatus.Finalized) revert LedgerFinalized(4);

        int64 amount = int64(uint64(amt / tx.gasprice));

        donorLedger.contributed -= amount;
        recipientLedger.requested -= amount;

        ledgers[donorAddress] = donorLedger;
        ledgers[recipientAddress] = recipientLedger;
    }


    function isInSurplus(address environment) external view returns (bool) {
        Lock memory mLock = lock;
        if (mLock.activeEnvironment != environment) return false;

        int64 totalBalanceDelta;
        int64 totalRequests;
        int64 totalContributions;

        uint256 activeParties = uint256(mLock.activeParties);
        for (uint256 i; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties & 1 << (i + 1) == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            Ledger memory partyLedger = ledgers[i];
            if (uint256(partyLedger.proxy) != i) {
                unchecked {
                    ++i;
                }
                continue;
            }

            totalBalanceDelta += partyLedger.balance;
            totalRequests += partyLedger.requested;
            totalContributions += partyLedger.contributed;

            unchecked {
                ++i;
            }
        }

        int64 atlasBalanceDelta = int64(uint64((ATLAS.balance) / tx.gasprice)) - int64(mLock.startingBalance);

        // If atlas balance is lower than expected, return false
        if (atlasBalanceDelta < totalRequests + totalContributions + totalBalanceDelta) return false;

        // If the requests have not yet been met, return false
        if (totalRequests + totalContributions < 0) return false;

        // Otherwise return true
        return true;
    }

    function balance(
        uint256 accruedGasRebate,
        address user,
        address dapp,
        address winningSolver,
        address bundler
    )
        external
    {
        Lock memory mLock = lock;
        uint256 activeParties = uint256(mLock.activeParties);

        int64 totalRequests;
        int64 totalContributions;
        int64 totalBalanceDelta;

        Ledger[LEDGER_LENGTH] memory parties;

        (parties, activeParties, totalRequests, totalContributions, totalBalanceDelta) = _loadLedgers(activeParties);

        (parties, totalRequests, totalContributions, totalBalanceDelta) = _allocateGasRebate(
            parties, mLock.startingBalance, accruedGasRebate, totalRequests, totalContributions, totalBalanceDelta
        );

        console.log("");
        console.log("* * * * * ");
        console.log("INITIAL:");
        _consolePrint(parties, activeParties);
        console.log("_______");
        console.log("* * * * * ");
        console.log("");

        // First, remove overfilled requests (refunding to general pool)
        if (totalRequests > 0) {
            (parties, totalRequests, totalContributions) =
                _removeSurplusRequests(parties, activeParties, totalRequests, totalContributions);
        }

        // Next, balance each party's surplus contributions against their own deficit requests
        (parties, totalRequests, totalContributions) =
            _balanceAgainstSelf(parties, activeParties, totalRequests, totalContributions);

        // Then allocate surplus contributions back to the correct parties
        if (totalRequests + totalContributions > 0) {
            (parties, totalRequests, totalContributions) =
                _allocateSurplusContributions(parties, activeParties, totalRequests, totalContributions);
        }

        console.log("* * * * * ");
        console.log("FINAL:");
        _consolePrint(parties, activeParties);
        console.log("_______");
        console.log("* * * * * ");

        // Finally, assign the balance deltas to the parties
        _assignBalanceDeltas(parties, activeParties, user, dapp, winningSolver, bundler);
    }

    function validParties(address environment, Party partyOne, Party partyTwo) external returns (bool valid) {
        return _validParties(environment, partyOne, partyTwo);
    }


    function reconcile(
        address environment,
        address searcherFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (bool)
    {
        // NOTE: approvedAmount is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe.  This will be subtracted later - tx will revert here if there isn't
        // enough.

        if (lock.activeEnvironment != environment) return false;
        if (parties[uint256(Party.Solver)] != searcherFrom) return false;

        Ledger memory partyLedger = ledgers[searcherFrom];
        if (partyLedger.status == LedgerStatus.Finalized) {
            return false;
        }

        if (msg.value != 0) {
            int64 amount = int64(uint64((msg.value) / tx.gasprice));
            partyLedger.balance += amount;
        }

        if (maxApprovedGasSpend != 0) {
            uint256 solverSurplusBalance =
                balanceOf[searcherFrom] - (EscrowBits.SOLVER_GAS_LIMIT * tx.gasprice + 1);
            maxApprovedGasSpend =
                maxApprovedGasSpend > solverSurplusBalance ? solverSurplusBalance : maxApprovedGasSpend;

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
        ledgers[searcherFrom] = partyLedger;
        return true;
    }

    // ---------------------------------------
    //              INTERNAL HELPERS
    // ---------------------------------------

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
                unchecked {
                    ++i;
                }
                continue;
            }

            Ledger memory partyLedger = ledgers[i];

            if (partyLedger.contributed < 0) revert NoUnfilledRequests();

            if (uint256(partyLedger.proxy) == i) {
                // Only tally totals from non-proxies
                totalBalanceDelta += partyLedger.balance;
                totalRequests += partyLedger.requested;
                totalContributions += partyLedger.contributed;
            } else {
                // Mark inactive if proxy
                activeParties = activeParties.markInactive(Party(i));
            }

            parties[i] = partyLedger;

            unchecked {
                ++i;
            }
        }

        return (parties, activeParties, totalRequests, totalContributions, totalBalanceDelta);
    }

    function _allocateGasRebate(
        Ledger[LEDGER_LENGTH] memory parties,
        uint64 startingGasBal,
        uint256 accruedGasRebate,
        int64 totalRequests,
        int64 totalContributions,
        int64 totalBalanceDelta
    )
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

        if (totalRequests + totalContributions < 0) revert MissingFunds(1);

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
        Ledger[LEDGER_LENGTH] memory parties,
        uint256 activeParties,
        int64 totalRequests,
        int64 totalContributions
    )
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

            if (partyLedger.requested < 0 && partyLedger.contributed > 0) {
                // CASE: Some Requests still in Deficit

                if (partyLedger.contributed + partyLedger.requested > 0) {
                    // CASE: Contributions > Requests

                    totalRequests -= partyLedger.requested; // subtracting a negative
                    totalContributions += partyLedger.requested; // adding a negative

                    partyLedger.contributed += partyLedger.requested; // adding a negative
                    partyLedger.requested = 0;
                } else {
                    // CASE: Requests >= Contributions

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
        Ledger[LEDGER_LENGTH] memory parties,
        uint256 activeParties,
        int64 totalRequests,
        int64 totalContributions
    )
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

        for (uint256 i; i < LEDGER_LENGTH && totalRequests > 0;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked {
                    ++i;
                }
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
            unchecked {
                ++i;
            }
        }

        return (parties, totalRequests, totalContributions);
    }

    function _allocateSurplusContributions(
        Ledger[LEDGER_LENGTH] memory parties,
        uint256 activeParties,
        int64 totalRequests,
        int64 totalContributions
    )
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
        uint256 activeParties,
        address user,
        address dapp,
        address winningSolver,
        address bundler
    )
        internal
    {
        for (uint256 i = 0; i < LEDGER_LENGTH;) {
            // If party has not been touched, skip it
            if (activeParties.isInactive(i)) {
                unchecked {
                    ++i;
                }
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

            unchecked {
                ++i;
            }
        }
    }

    function _consolePrint(Ledger[LEDGER_LENGTH] memory parties, uint256 activeParties) internal view {
        for (uint256 i = 0; i < LEDGER_LENGTH; i++) {
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
    function _partyAddress(
        uint256 index,
        address user,
        address dapp,
        address winningSolver,
        address bundler
    )
        internal
        view
        returns (address)
    {
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

    // ---------------------------------------
    //            MISC DEPENDENCIES
    // ---------------------------------------

    function _getActiveParties() internal view returns (uint256 activeParties) {
        Lock memory mLock = lock;
        activeParties = uint256(mLock.activeParties);
    }

    function _saveActiveParties(uint256 activeParties) internal {
        lock.activeParties = uint16(activeParties);
    }

    // NOTE: Not used except to set an immutable in Storage.sol
    function _computeDomainSeparator() internal view virtual override returns (bytes32) {
        return bytes32(0);
    }
}
