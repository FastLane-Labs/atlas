//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {SafetyBits} from "../libraries/SafetyBits.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {PartyMath} from "../libraries/GasParties.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";

import "../types/LockTypes.sol";

import {Storage} from "./Storage.sol";
import {FastLaneErrorsEvents} from "../types/Emissions.sol";
import {SafetyLocksLib} from "./SafetyLocksLib.sol";

import "forge-std/Test.sol";

abstract contract SafetyLocks is Storage, FastLaneErrorsEvents {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;
    using PartyMath for Party;
    using PartyMath for uint256;

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _safetyLocksLib,
        address _simulator
    ) Storage(_escrowDuration, _factory, _verification, _gasAccLib, _safetyLocksLib, _simulator) {}

    function _initializeEscrowLock(UserOperation calldata userOp, address executionEnvironment, address bundler, uint256 gasLimit) internal {
        (bool success,) = SAFETY_LOCKS_LIB.delegatecall(abi.encodeWithSelector(SafetyLocksLib.initializeEscrowLock.selector, userOp, executionEnvironment, bundler, gasLimit)); 
        if(!success) revert SafetyLocksLibError();
    }

    function _buildEscrowLock(
        DAppConfig calldata dConfig,
        address executionEnvironment,
        uint8 solverOpCount,
        bool isSimulation
    ) internal view returns (EscrowKey memory self) {

        // TODO: can we bypass this check?
        if(lock.activeEnvironment != executionEnvironment) revert NotInitialized();

        self = self.initializeEscrowLock(
            dConfig.callConfig.needsPreOpsCall(), solverOpCount, executionEnvironment, isSimulation
        );
    }

    function _releaseEscrowLock() internal {
        lock = Lock({
            activeEnvironment: UNLOCKED,
            activeParties: uint16(0),
            startingBalance: uint64(0)
        });

        for (uint256 i; i < LEDGER_LENGTH; i++) {
            // init the storage vars
            ledgers[i] = Ledger({
                balance: 0,
                contributed: 0,
                requested: 0,
                status: LedgerStatus.Inactive,
                proxy: Party(i)
            }); 
        }
    }

    function _getActiveParties() internal view returns (uint256 activeParties) {
        Lock memory mLock = lock;
        activeParties = uint256(mLock.activeParties);
    }

    function _saveActiveParties(uint256 activeParties) internal {
        lock.activeParties = uint16(activeParties);
    }

    function _checkIfUnlocked() internal view {
        if(lock.activeEnvironment != UNLOCKED) revert AlreadyInitialized();
    }

    function activeEnvironment() external view returns (address) {
        return lock.activeEnvironment;
    }
}
