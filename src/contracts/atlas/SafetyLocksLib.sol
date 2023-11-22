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
        address _factory,
        address _verification,
        address _gasAccLib,
        // address _safetyLocksLib,
        address _simulator,
        address _atlas
    )
        Storage(_escrowDuration, _factory, _verification, _gasAccLib, address(this), _simulator)
    {
        ATLAS = _atlas;
    }

    function initializeEscrowLock(
        UserOperation calldata userOp,
        address executionEnvironment,
        address bundler,
        address sequencer,
        uint256 gasLimit
    )
        external
        payable
    {
        _checkIfUnlocked();

        uint256 activeParties;
        activeParties = activeParties.markActive(Party.Bundler);
        activeParties = activeParties.markActive(Party.Solver);

        parties[uint256(Party.Bundler)]  = bundler;
        if (sequencer != INACTIVE) parties[uint256(Party.Sequencer)]  = sequencer;
        parties[uint256(Party.Solver)]  = SOLVER_PROXY;
        parties[uint256(Party.User)]  = userOp.from;
        parties[uint256(Party.DApp)]  = userOp.control;

        // Initialize Ledger
        int64 bundlerDeposit;
        int64 solverRequest = -int64(uint64(gasLimit));

        if (msg.value != 0) {
            bundlerDeposit = int64(uint64(msg.value / tx.gasprice));
            solverRequest -= bundlerDeposit;
        } 

        activeParties = activeParties.markActive(Party.Bundler);
        ledgers[bundler] = Ledger({
            balance: 0,
            contributed: bundlerDeposit,
            requested: solverRequest,
            status: LedgerStatus.Active
        });

        if (userOp.value != 0) {
            int64 userValue = int64(uint64(userOp.value / tx.gasprice));
            solverRequest -= userValue;

            if (userOp.from == bundler) {
                ledgers[userOp.from].requested -= userValue;
            } else {
                activeParties = activeParties.markActive(Party.User);
                ledgers[userOp.from] = Ledger({
                    balance: 0,
                    contributed: 0,
                    requested: 0 - userValue,
                    status: LedgerStatus.Active
                });
            }
        }

        activeParties = activeParties.markActive(Party.Solver);
        ledgers[SOLVER_PROXY] = Ledger({
            balance: 0,
            contributed: solverRequest,
            requested: 0,
            status: LedgerStatus.Active
        });

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
