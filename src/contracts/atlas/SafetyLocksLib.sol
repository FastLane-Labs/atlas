//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Storage } from "./Storage.sol";
import { FastLaneErrorsEvents } from "../types/Emissions.sol";

import { SafetyBits } from "../libraries/SafetyBits.sol";
import { CallBits } from "../libraries/CallBits.sol";
import { PartyMath } from "../libraries/GasParties.sol";

import "../types/UserCallTypes.sol";
import "../types/LockTypes.sol";
import "../types/EscrowTypes.sol";

// TODO check for address(this) or other assumptions from when inside Atlas inheritance

contract SafetyLocksLib is Storage, FastLaneErrorsEvents {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;
    using PartyMath for Party;
    using PartyMath for uint256;

    address public immutable ATLAS;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _gasAccLib,
        address _simulator,
        address _atlas
    )
        Storage(_escrowDuration, _verification, _gasAccLib, address(this), _simulator)
    {
        ATLAS = _atlas;
    }

    function initializeEscrowLock(
        UserOperation calldata userOp,
        address executionEnvironment,
        address bundler,
        uint256 gasLimit
    )
        external
        payable
    {
        _checkIfUnlocked();

        uint256 activeParties;
        activeParties = activeParties.markActive(Party.Bundler);
        activeParties = activeParties.markActive(Party.Solver);

        uint256 bundlerIndex = uint256(Party.Bundler);

        // Check for proxies
        // NOTE: Order is important here so that we can loop through these later without having to go backwards to find
        // final proxy
        // Builder proxy
        if (block.coinbase == bundler) {
            activeParties = activeParties.markActive(Party.Builder);
            ledgers[uint256(Party.Builder)] =
                Ledger({ balance: 0, contributed: 0, requested: 0, status: LedgerStatus.Proxy, proxy: Party.Bundler });
        } else if (block.coinbase == userOp.from) {
            activeParties = activeParties.markActive(Party.Builder);
            ledgers[uint256(Party.Builder)] =
                Ledger({ balance: 0, contributed: 0, requested: 0, status: LedgerStatus.Proxy, proxy: Party.User });
        }

        // Bundler proxy
        if (bundler == userOp.from) {
            // Bundler already marked active
            ledgers[uint256(Party.Bundler)] =
                Ledger({ balance: 0, contributed: 0, requested: 0, status: LedgerStatus.Proxy, proxy: Party.User });
            bundlerIndex = uint256(Party.User);
        }

        // Initialize Ledger
        int64 iGasLimit = int64(uint64(gasLimit));

        if (msg.value != 0) {
            int64 bundlerDeposit = int64(uint64(msg.value / tx.gasprice));
            ledgers[bundlerIndex] = Ledger({
                balance: 0,
                contributed: bundlerDeposit,
                requested: 0 - bundlerDeposit - iGasLimit,
                status: LedgerStatus.Active,
                proxy: Party(bundlerIndex)
            });
        } else {
            ledgers[bundlerIndex] = Ledger({
                balance: 0,
                contributed: 0,
                requested: 0 - iGasLimit,
                status: LedgerStatus.Active,
                proxy: Party(bundlerIndex)
            });
        }

        // Initialize the Lock
        lock = Lock({
            activeEnvironment: executionEnvironment,
            activeParties: uint16(activeParties),
            startingBalance: uint64((address(this).balance - msg.value) / tx.gasprice)
        });
    }

    function _checkIfUnlocked() internal view {
        if (lock.activeEnvironment != UNLOCKED) revert AlreadyInitialized();
    }
}
