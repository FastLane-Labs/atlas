//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafetyBits} from "../libraries/SafetyBits.sol";
import {CallBits} from "../libraries/CallBits.sol";
import {GasPartyMath} from "../libraries/GasParties.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";

import "../types/LockTypes.sol";

import "forge-std/Test.sol";

contract SafetyLocks {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;
    using GasPartyMath for GasParty;
    using GasPartyMath for uint256;

    address public immutable atlas;
    address public immutable simulator;

    address internal constant UNLOCKED = address(1);
    
    Lock public lock;

    uint256 constant internal _ledgerLength = 5; // uint256(type(GasParty).max); // 6
    Ledger[_ledgerLength] public ledgers;

    constructor(address _simulator) {
        atlas = address(this);
        simulator = _simulator;

        lock = Lock({
            activeEnvironment: UNLOCKED,
            activeParties: uint16(0),
            startingBalance: uint64(0)
        });

        for (uint256 i; i < _ledgerLength; i++) {
            ledgers[i].status = LedgerStatus.Inactive; // init the storage vars
        }
    }

    function _initializeEscrowLock(UserOperation calldata userOp, address executionEnvironment, uint256 gasLimit) onlyWhenUnlocked internal {

        uint256 activeParties;
        activeParties = activeParties.markActive(GasParty.Bundler);
        activeParties = activeParties.markActive(GasParty.Solver);

        int64 iGasLimit = int64(uint64(gasLimit));

        if (msg.value != 0) {
            int64 bundlerDeposit = int64(uint64(msg.value / tx.gasprice));
            ledgers[uint256(GasParty.Bundler)] = Ledger({
                balance: 0,
                contributed: bundlerDeposit,
                requested: 0 - bundlerDeposit - iGasLimit,
                status: LedgerStatus.Active
            });
        } else {
            ledgers[uint256(GasParty.Bundler)] = Ledger({
                balance: 0,
                contributed: 0,
                requested: 0 - iGasLimit,
                status: LedgerStatus.Active
            });
        }

        if (userOp.value != 0) {
            activeParties = activeParties.markActive(GasParty.User);
            int64 userRequest = int64(uint64(userOp.value / tx.gasprice));
            ledgers[uint256(GasParty.Bundler)] = Ledger({
                balance: 0,
                contributed: 0,
                requested: userRequest,
                status: LedgerStatus.Active
            });
        }

        lock = Lock({
            activeEnvironment: executionEnvironment,
            activeParties: uint16(activeParties),
            startingBalance: uint64((address(this).balance - msg.value) / tx.gasprice)
        });
    }

    function _buildEscrowLock(
        DAppConfig calldata dConfig,
        address executionEnvironment,
        uint8 solverOpCount,
        bool isSimulation
    ) internal view returns (EscrowKey memory self) {

        require(lock.activeEnvironment == executionEnvironment, "ERR-SL004 NotInitialized");

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
    }

    modifier onlyWhenUnlocked() {
        require(lock.activeEnvironment == UNLOCKED, "ERR-SL003 AlreadyInitialized");
        _;
    }

    function activeEnvironment() external view returns (address) {
        return lock.activeEnvironment;
    }
}
