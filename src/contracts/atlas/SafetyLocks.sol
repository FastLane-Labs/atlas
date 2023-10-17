//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafetyBits} from "../libraries/SafetyBits.sol";
import {CallBits} from "../libraries/CallBits.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/EscrowTypes.sol";

import "../types/LockTypes.sol";

contract SafetyLocks {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;

    address public immutable atlas;
    address public immutable simulator;

    address internal constant UNLOCKED = address(1);

    struct Lock {
        address activeEnvironment;
        uint64 activeParties; // bitmap
    }
    
    Lock public lock;

    constructor(address _simulator) {
        atlas = address(this);
        simulator = _simulator;

        lock = Lock({
            activeEnvironment: UNLOCKED,
            activeParties: uint64(0)
        });
    }

    // TODO can we remove this? solver value repayment handled in Escrow.sol now
    function solverSafetyCallback(address msgSender) external payable returns (bool isSafe) {
        // An external call so that solver contracts can verify
        // that delegatecall isn't being abused.

        isSafe = msgSender == lock.activeEnvironment;
    }

    function _initializeEscrowLock(UserOperation calldata userOp, address executionEnvironment) onlyWhenUnlocked internal {

        uint256 activeParties;
        if (msg.value != 0) {
            activeParties |= 1 << uint256(GasParty.Bundler);
        }
        if (userOp.value != 0) {
            activeParties |= 1 << uint256(GasParty.User);
        }

        lock = Lock({
            activeEnvironment: executionEnvironment,
            activeParties: uint64(activeParties)
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
            activeParties: uint64(0)
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
