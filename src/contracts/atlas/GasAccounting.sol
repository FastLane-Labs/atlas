//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafetyLocks } from "../atlas/SafetyLocks.sol";

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";
import { SolverOperation } from "../types/SolverCallTypes.sol";

import { EscrowBits } from "../libraries/EscrowBits.sol";

// import "forge-std/Test.sol"; //TODO remove

abstract contract GasAccounting is SafetyLocks {
    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator
    )
        SafetyLocks(_escrowDuration, _verification, _simulator)
    { }

    // ---------------------------------------
    //          EXTERNAL FUNCTIONS
    // ---------------------------------------

    // Returns true if Solver status is Finalized and the caller (Execution Environment) is in surplus
    function validateBalances() external view returns (bool valid) {
        return solver == SOLVER_FULFILLED;
    }

    function contribute() external payable {
        if (lock != msg.sender) revert InvalidExecutionEnvironment(lock);
        _contribute();
    }

    function borrow(uint256 amount) external payable {
        if (lock != msg.sender) revert InvalidExecutionEnvironment(lock);
        if (_borrow(amount)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert InsufficientAtlETHBalance(address(this).balance, amount);
        }
    }

    function shortfall() external view returns (uint256) {
        uint256 deficit = claims + withdrawals;
        uint256 _deposits = deposits;
        return (deficit > _deposits) ? (deficit - _deposits) : 0;
    }

    function reconcile(
        address environment,
        address solverFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (bool)
    {
        // NOTE: approvedAmount is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe.  This will be subtracted later - tx will revert here if there isn't
        // enough.

        EscrowAccountData memory solverEscrow = _balanceOf[solverFrom];

        if (lock != environment) revert InvalidExecutionEnvironment(lock);
        if (solverFrom != solver) revert InvalidSolverFrom(solver);
        if (uint256(solverEscrow.balance) - uint256(solverEscrow.holds) < maxApprovedGasSpend) {
            revert InsufficientSolverBalance(
                uint256(_balanceOf[solverFrom].balance),
                msg.value,
                uint256(_balanceOf[solverFrom].holds),
                maxApprovedGasSpend
            );
        }

        uint256 _deposits = deposits;

        uint256 deficit = claims + withdrawals;
        uint256 surplus = _deposits + msg.value + maxApprovedGasSpend;

        if (deficit > surplus) revert InsufficientTotalBalance(deficit - surplus);

        // Increase solver holds by the approved amount - which will decrease solver's balance to pay for gas used
        solverEscrow.holds += uint128(maxApprovedGasSpend);
        _balanceOf[solverFrom] = solverEscrow;

        // Add (msg.value + maxApprovedGasSpend) to solver's deposits
        deposits = surplus;

        solver = SOLVER_FULFILLED;

        return true;
    }

    function _contribute() internal {
        if (msg.value != 0) deposits += msg.value;
    }

    function _borrow(uint256 amount) internal returns (bool valid) {
        if (amount == 0) return true;
        if (address(this).balance < amount) return false;
        withdrawals += amount;
        return true;
    }

    function _trySolverLock(SolverOperation calldata solverOp) internal returns (bool valid) {
        if (_borrow(solverOp.value)) {
            address solverFrom = solverOp.from;
            nonces[solverFrom].lastAccessed = uint64(block.number);
            solver = solverFrom;
            return true;
        } else {
            return false;
        }
    }

    function _releaseSolverLock(SolverOperation calldata solverOp, uint256 gasWaterMark, uint256 result) internal {
        // Calculate what the solver owes if they failed
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        address solverFrom = solverOp.from;
        uint256 solverBalance = (_balanceOf[solverFrom].balance);

        uint256 gasUsed = gasWaterMark - gasleft() + 5000;
        if (result & EscrowBits._FULL_REFUND != 0) {
            gasUsed = gasUsed + (solverOp.data.length * CALLDATA_LENGTH_PREMIUM) + 1;
        } else if (result & EscrowBits._CALLDATA_REFUND != 0) {
            gasUsed = (solverOp.data.length * CALLDATA_LENGTH_PREMIUM) + 1;
        } else if (result & EscrowBits._NO_USER_REFUND != 0) {
            return;
        } else {
            revert UncoveredResult();
        }

        gasUsed = (gasUsed + ((gasUsed * SURCHARGE) / SURCHARGE_BASE)) * tx.gasprice;

        gasUsed = gasUsed > solverBalance ? solverBalance : gasUsed;

        _balanceOf[solverFrom].balance -= uint128(gasUsed);

        deposits += gasUsed;
    }

    function _settle(address winningSolver, address bundler) internal {
        // NOTE: If there is no winningSolver but the dApp config allows unfulfilled 'successes,' the bundler
        // is treated as the Solver.

        // Load what we can from storage so that it shows up in the gasleft() calc
        uint256 _surcharge = surcharge;
        uint256 _claims = claims;
        uint256 _withdrawals = withdrawals;
        uint256 _deposits = deposits;
        uint256 _supply = totalSupply;

        EscrowAccountData memory solverEscrow = _balanceOf[winningSolver];
        uint256 _solverHold = solverEscrow.holds;

        // Remove any remaining gas from the bundler's claim.
        uint256 gasRemainder = (gasleft() * tx.gasprice);
        gasRemainder += ((gasRemainder * SURCHARGE) / SURCHARGE_BASE);
        _claims -= gasRemainder;

        if (_deposits < _claims + _withdrawals) revert InsufficientTotalBalance((_claims + _withdrawals) - _deposits);

        uint256 surplus = _deposits - _claims - _withdrawals;

        // Remove the hold
        // NOTE that holds can also be applied from withdrawals, so make sure we don't remove any non-transitory holds
        if (surplus > _solverHold) {
            surplus -= _solverHold;
            solverEscrow.holds = 0;
            solverEscrow.balance += uint128(surplus);
        } else {
            solverEscrow.holds -= uint128(surplus);
            surplus = 0;
        }

        uint256 netGasSurcharge = (_claims * SURCHARGE) / SURCHARGE_BASE;

        _claims -= netGasSurcharge;

        _balanceOf[winningSolver] = solverEscrow;

        surcharge = _surcharge + netGasSurcharge;

        SafeTransferLib.safeTransferETH(bundler, _claims);
    }
}
