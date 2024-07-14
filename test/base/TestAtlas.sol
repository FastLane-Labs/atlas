//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "src/contracts/atlas/Atlas.sol";

/// @title TestAtlas
/// @author FastLane Labs
/// @notice A test version of the Atlas contract that just exposes internal transient storage helpers.
contract TestAtlas is Atlas {
    constructor(
        uint256 escrowDuration,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator,
        address executionTemplate
    )
        Atlas(escrowDuration, verification, simulator, initialSurchargeRecipient, l2GasCalculator, executionTemplate)
    { }

    // Public functions to expose internal transient helpers for testing

    function clearTransientStorage() public {
        _setLock(address(0), 0, 0);
        _setSolverLock(0);
        _setSolverTo(address(0));
        _setClaims(0);
        _setFees(0);
        _setWriteoffs(0);
        _setWithdrawals(0);
        _setDeposits(0);
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
        _setClaims(newClaims);
    }

    function setFees(uint256 newFees) public {
        _setFees(newFees);
    }

    function setWriteoffs(uint256 newWriteoffs) public {
        _setWriteoffs(newWriteoffs);
    }

    function setWithdrawals(uint256 newWithdrawals) public {
        _setWithdrawals(newWithdrawals);
    }

    function setDeposits(uint256 newDeposits) public {
        _setDeposits(newDeposits);
    }

    // View functions

    function getClaims() external view returns (uint256) {
        return claims();
    }

    function getFees() external view returns (uint256) {
        return fees();
    }

    function getWriteoffs() external view returns (uint256) {
        return writeoffs();
    }

    function getWithdrawals() external view returns (uint256) {
        return withdrawals();
    }

    function getDeposits() external view returns (uint256) {
        return deposits();
    }
}
