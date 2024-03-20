//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafetyLocks } from "../atlas/SafetyLocks.sol";

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";
import { SolverOperation } from "../types/SolverCallTypes.sol";

import { EscrowBits } from "../libraries/EscrowBits.sol";

import "forge-std/Test.sol"; //TODO remove

abstract contract GasAccounting is SafetyLocks {
    using EscrowBits for uint256;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        SafetyLocks(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    // ---------------------------------------
    //          EXTERNAL FUNCTIONS
    // ---------------------------------------

    // Returns true if Solver status is Finalized and the caller (Execution Environment) is in surplus
    function validateBalances() external view returns (bool valid) {
        (, bool calledBack, bool fulfilled) = solverLockData();
        if (!calledBack) {
            return false;
        }

        if (!fulfilled) {
            return (deposits >= claims + withdrawals);
        }
        return true;
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
        returns (uint256 owed)
    {
        // NOTE: approvedAmount is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe.  This will be subtracted later - tx will revert here if there isn't
        // enough.

        uint256 bondedBalance = uint256(accessData[solverFrom].bonded);

        if (maxApprovedGasSpend > bondedBalance) maxApprovedGasSpend = bondedBalance;

        if (lock != environment) revert InvalidExecutionEnvironment(lock);

        (address currentSolver, bool calledBack, bool fulfilled) = solverLockData();

        if (solverFrom != currentSolver) revert InvalidSolverFrom(currentSolver);

        uint256 deficit = claims + withdrawals;
        uint256 surplus = deposits + maxApprovedGasSpend + msg.value;

        // if (deficit > surplus) revert InsufficientTotalBalance(deficit - surplus);

        // Add msg.value to solver's deposits
        if (msg.value > 0 || maxApprovedGasSpend > 0) deposits = surplus;

        // CASE: Callback verified but insufficient balance
        if (deficit > surplus) {
            if (!calledBack) {
                _solverLock = uint256(uint160(currentSolver)) | _solverCalledBack;
            }
            return deficit - surplus;
        }

        // CASE: Callback verified and solver duty fulfilled
        if (!calledBack || !fulfilled) {
            _solverLock = uint256(uint160(currentSolver)) | _solverCalledBack | _solverFulfilled;
        }
        return 0;
    }

    // ---------------------------------------
    //          INTERNAL FUNCTIONS
    // ---------------------------------------

    function _contribute() internal {
        if (msg.value != 0) deposits += msg.value;
    }

    function _borrow(uint256 amount) internal returns (bool valid) {
        if (amount == 0) return true;
        if (address(this).balance < amount + claims + withdrawals) return false;
        withdrawals += amount;
        return true;
    }

    // Takes AtlETH from 1) owner's bonded balance, and if more needed, also from 2) owner's unbonding balance
    // and increases transient solver deposits by this amount
    function _assign(address owner, uint256 amount, bool solverWon, bool bidFind) internal returns (bool isDeficit) {
        if (amount == 0) {
            accessData[owner].lastAccessedBlock = uint32(block.number); // still save on bidFind
        } else {
            if (amount > type(uint112).max) revert ValueTooLarge();
            uint112 amt = uint112(amount);

            EscrowAccountAccessData memory aData = accessData[owner];

            if (aData.bonded < amt) {
                // CASE: Not enough bonded balance to cover amount owed
                EscrowAccountBalance memory bData = _balanceOf[owner];
                if (bData.unbonding + aData.bonded < amt) {
                    isDeficit = true;
                    amount = uint256(bData.unbonding + aData.bonded); // contribute less to deposits ledger
                    _balanceOf[owner].unbonding = 0;
                    aData.bonded = 0;
                } else {
                    _balanceOf[owner].unbonding = bData.unbonding + aData.bonded - amt;
                    aData.bonded = 0;
                }
            } else {
                aData.bonded -= amt;
            }

            if (!bidFind) {
                aData.lastAccessedBlock = uint32(block.number);
            }

            // Reputation Analytics: Track total gas used, solver wins, and failures
            aData.totalGasUsed += uint64(amount / GAS_USED_DECIMALS_TO_DROP);
            if (solverWon) {
                aData.auctionWins++;
            } else if (!bidFind) {
                aData.auctionFails++;
            }

            accessData[owner] = aData;

            bondedTotalSupply -= amount;
            deposits += amount;
        }
    }

    // Increases owner's bonded balance by amount
    function _credit(address owner, uint256 amount) internal {
        if (amount > type(uint112).max) revert ValueTooLarge();
        uint112 amt = uint112(amount);

        EscrowAccountAccessData memory aData = accessData[owner];

        aData.lastAccessedBlock = uint32(block.number);
        aData.bonded += amt;

        bondedTotalSupply += amount;

        accessData[owner] = aData;
    }

    function _trySolverLock(SolverOperation calldata solverOp) internal returns (bool valid) {
        if (_borrow(solverOp.value)) {
            _solverLock = uint256(uint160(solverOp.from));
            return true;
        } else {
            return false;
        }
    }

    function _releaseSolverLock(
        SolverOperation calldata solverOp, uint256 gasWaterMark, uint256 result, bool bidFind, bool includeCalldata
    ) 
        internal 
    {
        // Calculate what the solver owes if they failed
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        if (!bidFind && !result.updateEscrow()) return;

        uint256 gasUsed = (gasWaterMark - gasleft() + 5000) * tx.gasprice;
        
        if (includeCalldata) {
            gasUsed += _getCalldataCost(solverOp.data.length);
        }

        gasUsed = (gasUsed + ((gasUsed * SURCHARGE) / SURCHARGE_BASE));
        _assign(solverOp.from, gasUsed, false, bidFind);
    }

    function _settle(address winningSolver, address bundler) internal {
        // NOTE: If there is no winningSolver but the dApp config allows unfulfilled 'successes,' the bundler
        // is treated as the Solver.

        // Load what we can from storage so that it shows up in the gasleft() calc
        uint256 _surcharge = surcharge;
        uint256 _claims = claims;
        uint256 _withdrawals = withdrawals;
        uint256 _deposits = deposits;

        // Remove any unused gas from the bundler's claim.
        // TODO: consider penalizing bundler for too much unused gas (to prevent high escrow requirements for solvers)
        uint256 gasRemainder = (gasleft() * tx.gasprice);
        gasRemainder += ((gasRemainder * SURCHARGE) / SURCHARGE_BASE);
        _claims -= gasRemainder;

        if (_deposits < _claims + _withdrawals) {
            // CASE: in deficit, subtract from bonded balance
            uint256 amountOwed = _claims + _withdrawals - _deposits;
            if (_assign(winningSolver, amountOwed, true, false)) {
                revert InsufficientTotalBalance((_claims + _withdrawals) - deposits);
            }
        } else {
            // CASE: in surplus, add to bonded balance
            // TODO: make sure this works w/ the surcharge 10%
            uint256 amountCredited = _deposits - _claims - _withdrawals;
            _credit(winningSolver, amountCredited);
        }

        uint256 netGasSurcharge = (_claims * SURCHARGE) / SURCHARGE_BASE;

        _claims -= netGasSurcharge;

        surcharge = _surcharge + netGasSurcharge;

        SafeTransferLib.safeTransferETH(bundler, _claims);
        emit GasRefundSettled(bundler, _claims);
    }

    function _getCalldataCost(uint256 calldataLength) internal view returns (uint256 calldataCost) {
        // Alter this for L2s.
        // TODO: replace 128 w/ actual extra length of calldata that isn't in the 
        // solverOp.data field (from, to, etc)
        calldataCost = (calldataLength + 128) * CALLDATA_LENGTH_PREMIUM * tx.gasprice;
    }
}
