//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../src/contracts/atlas/Atlas.sol";

/// @title TestAtlas
/// @author FastLane Labs
/// @notice A test version of the Atlas contract that just exposes internal transient storage helpers.
contract TestAtlas is Atlas {
    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        uint256 bundlerSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator,
        address executionTemplate
    )
        Atlas(
            escrowDuration,
            atlasSurchargeRate,
            bundlerSurchargeRate,
            verification,
            simulator,
            initialSurchargeRecipient,
            l2GasCalculator,
            executionTemplate
        )
    { }

    // Public functions to expose internal transient helpers for testing

    function clearTransientStorage() public {
        _setLock(address(0), 0, 0);
        _setSolverLock(0);
        _setSolverTo(address(0));
        claims = 0;
        fees = 0;
        writeoffs = 0;
        withdrawals = 0;
        deposits = 0;
        solverSurcharge = 0;
    }

    function setLock(address activeEnvironment, uint32 callConfig, uint8 phase) public {
        _setLock(activeEnvironment, callConfig, phase);
    }

    function setLockPhase(ExecutionPhase newPhase) public {
        _setLockPhase(uint8(newPhase));
    }

    function setSolverLock(uint256 newSolverLock) public {
        _setSolverLock(newSolverLock);
    }

    function setSolverTo(address newSolverTo) public {
        _setSolverTo(newSolverTo);
    }

    function setClaims(uint256 newClaims) public {
        claims = newClaims;
    }

    function setFees(uint256 newFees) public {
        fees = newFees;
    }

    function setWriteoffs(uint256 newWriteoffs) public {
        writeoffs = newWriteoffs;
    }

    function setWithdrawals(uint256 newWithdrawals) public {
        withdrawals = newWithdrawals;
    }

    function setDeposits(uint256 newDeposits) public {
        deposits = newDeposits;
    }
}
