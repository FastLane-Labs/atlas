//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../src/contracts/atlas/Atlas.sol";
import { GasAccLib, GasLedger, BorrowsLedger } from "../../src/contracts/libraries/GasAccLib.sol";

/// @title TestAtlas
/// @author FastLane Labs
/// @notice A test version of the Atlas contract that just exposes internal transient storage helpers.
contract TestAtlas is Atlas {
    using GasAccLib for uint256;

    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        uint256 bundlerSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator,
        address factoryLib
    )
        Atlas(
            escrowDuration,
            atlasSurchargeRate,
            bundlerSurchargeRate,
            verification,
            simulator,
            initialSurchargeRecipient,
            l2GasCalculator,
            factoryLib
        )
    { }

    // Public functions to expose internal transient helpers for testing

    function clearTransientStorage() public {
        _setLock(address(0), 0, 0);
        t_solverLock = 0;
        t_solverTo = address(0);
        t_gasLedger = 0;
        t_borrowsLedger = 0;
    }

    // Transient Setters

    function setLock(address activeEnvironment, uint32 callConfig, uint8 phase) public {
        _setLock(activeEnvironment, callConfig, phase);
    }

    function setLockPhase(ExecutionPhase newPhase) public {
        _setLockPhase(uint8(newPhase));
    }

    function setSolverLock(uint256 newSolverLock) public {
        t_solverLock = newSolverLock;
    }

    function setSolverTo(address newSolverTo) public {
        t_solverTo = newSolverTo;
    }

    function setGasLedger(uint256 newGasLedger) public {
        t_gasLedger = newGasLedger;
    }

    function setBorrowsLedger(uint256 newBorrowsLedger) public {
        t_borrowsLedger = newBorrowsLedger;
    }

    // Transient Getters

    function getGasLedger() public view returns (GasLedger memory gL) {
        return t_gasLedger.toGasLedger();
    }

    function getBorrowsLedger() public view returns (BorrowsLedger memory bL) {
        return t_borrowsLedger.toBorrowsLedger();
    }
}
