//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafetyBits} from "../libraries/SafetyBits.sol";
import {CallBits} from "../libraries/CallBits.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import "../types/LockTypes.sol";

import "forge-std/Test.sol";

contract SafetyLocks is Test {
    using SafetyBits for EscrowKey;
    using CallBits for uint32;

    address public immutable atlas;
    address public immutable simulator;

    address internal constant UNLOCKED = address(1);

    address public activeEnvironment = UNLOCKED;

    constructor(address _simulator) {
        atlas = address(this);
        simulator = _simulator;
    }

    // TODO can we remove this? solver value repayment handled in Escrow.sol now
    function solverSafetyCallback(address msgSender) external payable returns (bool isSafe) {
        // An external call so that solver contracts can verify
        // that delegatecall isn't being abused.

        isSafe = msgSender == activeEnvironment;
    }

    function _initializeEscrowLock(address executionEnvironment) onlyWhenUnlocked internal {

        activeEnvironment = executionEnvironment;
    }

    function _buildEscrowLock(
        DAppConfig calldata dConfig,
        address executionEnvironment,
        uint8 solverOpCount,
        bool isSimulation
    ) internal view returns (EscrowKey memory self) {

        require(activeEnvironment == executionEnvironment, "ERR-SL004 NotInitialized");

        self = self.initializeEscrowLock(
            dConfig.callConfig.needsPreOpsCall(), solverOpCount, executionEnvironment, isSimulation
        );
    }

    function _releaseEscrowLock() internal {
        activeEnvironment = UNLOCKED;
    }

    modifier onlyWhenUnlocked() {
        require(activeEnvironment == UNLOCKED, "ERR-SL003 AlreadyInitialized");
        _;
    }
}
