//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { SafetyLocks } from "src/contracts/atlas/SafetyLocks.sol";
import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";

/// @title GasAccounting
/// @author FastLane Labs
/// @notice GasAccounting manages the accounting of gas surcharges and escrow balances for the Atlas protocol.
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

    /// @notice Contributes ETH to the contract, increasing the deposits if a non-zero value is sent.
    function contribute() external payable {
        if (lock != msg.sender) revert InvalidExecutionEnvironment(lock);
        _contribute();
    }

    /// @notice Borrows ETH from the contract, transferring the specified amount to the caller if available.
    /// @param amount The amount of ETH to borrow.
    function borrow(uint256 amount) external payable {
        if (lock != msg.sender) revert InvalidExecutionEnvironment(lock);
        if (_borrow(amount)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert InsufficientAtlETHBalance(address(this).balance, amount);
        }
    }

    /// @notice Calculates the current shortfall between deficit (claims + withdrawals) and deposits.
    /// @return The current shortfall amount, if any.
    function shortfall() external view returns (uint256) {
        uint256 deficit = claims + withdrawals;
        uint256 _deposits = deposits;
        return (deficit > _deposits) ? (deficit - _deposits) : 0;
    }

    /// @notice Reconciles the escrow balances and gas surcharge between the Execution Environment and the solver. This
    /// function adjusts the solver's bonded balance based on the actual gas spent and any additional payments or
    /// deductions.
    /// @param environment The Execution Environment contract address involved in the reconciliation.
    /// @param solverFrom The address of the solver from which the reconciliation is initiated.
    /// @param maxApprovedGasSpend The maximum amount of gas spend approved by the solver for covering transaction
    /// costs.
    /// @return owed The amount owed, if any, by the solver after reconciliation.
    function reconcile(
        address environment,
        address solverFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (uint256 owed)
    {
        // NOTE: maxApprovedGasSpend is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe. This will be subtracted later - tx will revert here if there isn't
        // enough.

        uint256 bondedBalance = uint256(accessData[solverFrom].bonded);

        if (maxApprovedGasSpend > bondedBalance) maxApprovedGasSpend = bondedBalance;

        if (lock != environment) revert InvalidExecutionEnvironment(lock);

        (address currentSolver, bool calledBack, bool fulfilled) = _solverLockData();

        if (calledBack) revert DoubleReconcile();

        if (solverFrom != currentSolver) revert InvalidSolverFrom(currentSolver);

        uint256 deficit = claims + withdrawals;
        uint256 surplus = deposits + maxApprovedGasSpend + msg.value;

        // if (deficit > surplus) revert InsufficientTotalBalance(deficit - surplus);

        // Add msg.value to solver's deposits
        if (msg.value > 0 || maxApprovedGasSpend > 0) deposits = surplus;

        // CASE: Callback verified but insufficient balance
        if (deficit > surplus) {
            _solverLock = uint256(uint160(currentSolver)) | _SOLVER_CALLED_BACK_MASK;

            return deficit - surplus;
        }

        // CASE: Callback verified and solver duty fulfilled
        if (!fulfilled) {
            _solverLock = uint256(uint160(currentSolver)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK;
        }
        return 0;
    }

    /// @notice Internal function to handle ETH contribution, increasing deposits if a non-zero value is sent.
    function _contribute() internal {
        if (msg.value != 0) deposits += msg.value;
    }

    /// @notice Borrows ETH from the contract, transferring the specified amount to the caller if available.
    /// @param amount The amount of ETH to borrow.
    /// @return valid A boolean indicating whether the borrowing operation was successful.
    function _borrow(uint256 amount) internal returns (bool valid) {
        if (amount == 0) return true;
        uint256 _withdrawals = withdrawals + amount;
        if (address(this).balance < claims + _withdrawals) return false;
        withdrawals = _withdrawals;
        return true;
    }

    /// @notice Takes AtlETH from the owner's bonded balance and, if necessary, from the owner's unbonding balance to
    /// increase transient solver deposits.
    /// @param owner The address of the owner from whom AtlETH is taken.
    /// @param amount The amount of AtlETH to be taken.
    /// @param solverWon A boolean indicating whether the solver won the bid.
    /// @param bidFind Indicates if called in the context of `_getBidAmount` in Escrow.sol (true) or not (false).
    /// @return isDeficit A boolean indicating whether there is a deficit after the assignment.
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

            _updateAnalytics(aData, amt, solverWon, bidFind);

            accessData[owner] = aData;

            bondedTotalSupply -= amount;
            deposits += amount;
        }
    }

    /// @notice Increases the owner's bonded balance by the specified amount.
    /// @param owner The address of the owner whose bonded balance will be increased.
    /// @param amount The amount by which to increase the owner's bonded balance.
    function _credit(address owner, uint256 amount) internal {
        if (amount > type(uint112).max) revert ValueTooLarge();
        uint112 amt = uint112(amount);

        EscrowAccountAccessData memory aData = accessData[owner];

        aData.lastAccessedBlock = uint32(block.number);
        aData.bonded += amt;

        bondedTotalSupply += amount;

        _updateAnalytics(aData, 0, true, false);

        accessData[owner] = aData;
    }

    /// @notice Attempts to lock the solver's operation by borrowing AtlETH.
    /// @dev If borrowing AtlETH is successful, sets the solver lock and returns true; otherwise, returns false.
    /// @param solverOp The SolverOperation data for the borrowing solver.
    /// @return valid True if the solver lock is successfully set, otherwise false.
    function _trySolverLock(SolverOperation calldata solverOp) internal returns (bool valid) {
        if (_borrow(solverOp.value)) {
            _solverLock = uint256(uint160(solverOp.from));
            return true;
        }

        return false;
    }

    /// @notice Releases the solver lock and adjusts the solver's escrow balance based on the gas used and other
    /// factors.
    /// @dev Calculates the gas used for the SolverOperation and adjusts the solver's escrow balance accordingly.
    /// @param solverOp The current SolverOperation for which to account
    /// @param gasWaterMark The `gasleft()` watermark taken at the start of executing the SolverOperation.
    /// @param result The result bitmap of the SolverOperation execution.
    /// @param bidFind Indicates if called in the context of `_getBidAmount` in Escrow.sol (true) or not (false).
    /// @param includeCalldata Whether to include calldata cost in the gas calculation.
    function _releaseSolverLock(
        SolverOperation calldata solverOp,
        uint256 gasWaterMark,
        uint256 result,
        bool bidFind,
        bool includeCalldata
    )
        internal
    {
        // Calculate what the solver owes if they failed
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        if (!bidFind && !result.updateEscrow()) return;

        uint256 gasUsed = (gasWaterMark - gasleft() + _SOLVER_LOCK_GAS_BUFFER) * tx.gasprice;

        if (includeCalldata) {
            gasUsed += _getCalldataCost(solverOp.data.length);
        }

        gasUsed = (gasUsed + ((gasUsed * SURCHARGE_RATE) / SURCHARGE_SCALE));
        _assign(solverOp.from, gasUsed, false, bidFind);
    }

    /// @notice Settles the transaction after execution, determining the final distribution of funds between the winning
    /// solver and the bundler based on the outcome.
    /// @dev This function adjusts the claims, withdrawals, deposits, and surcharges based on the gas used by the
    /// transaction.
    /// @param winningSolver The address of the winning solver.
    /// @param bundler The address of the bundler, who is refunded for the gas used during the transaction execution.
    function _settle(
        address winningSolver,
        address bundler
    )
        internal
        returns (uint256 claimsPaidToBundler, uint256 netGasSurcharge)
    {
        // NOTE: If there is no winningSolver but the dApp config allows unfulfilled 'successes,' the bundler
        // is treated as the Solver.

        // Load what we can from storage so that it shows up in the gasleft() calc
        uint256 _surcharge = cumulativeSurcharge;
        uint256 _claims = claims;
        uint256 _withdrawals = withdrawals;
        uint256 _deposits = deposits;

        // Remove any unused gas from the bundler's claim.
        // TODO: consider penalizing bundler for too much unused gas (to prevent high escrow requirements for solvers)
        uint256 gasRemainder = gasleft() * tx.gasprice;
        gasRemainder = gasRemainder * (SURCHARGE_SCALE + SURCHARGE_RATE) / SURCHARGE_SCALE;
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

        netGasSurcharge = (_claims * SURCHARGE_RATE) / SURCHARGE_SCALE;

        _claims -= netGasSurcharge;

        cumulativeSurcharge = _surcharge + netGasSurcharge;

        SafeTransferLib.safeTransferETH(bundler, _claims);

        return (_claims, netGasSurcharge);
    }

    /// @notice Calculates the gas cost of the calldata used to execute a SolverOperation.
    /// @param calldataLength The length of the `data` field in the SolverOperation.
    /// @return calldataCost The gas cost of the calldata used to execute the SolverOperation.
    function _getCalldataCost(uint256 calldataLength) internal view returns (uint256 calldataCost) {
        // NOTE: Alter this for L2s.

        // _SOLVER_OP_BASE_CALLDATA = SolverOperation calldata length excluding solverOp.data
        calldataCost = (calldataLength + _SOLVER_OP_BASE_CALLDATA) * _CALLDATA_LENGTH_PREMIUM * tx.gasprice;
    }

    /// @notice Reputation Analytics: Track total gas used, solver wins, and failures.
    /// @dev The aData struct is passed by reference. The calling function is responsible for updating the storage.
    /// @param aData The EscrowAccountAccessData for the solver.
    /// @param gasUsed The gas charged to the solver.
    /// @param solverWon A boolean indicating whether the solver won the auction.
    /// @param bidFind Indicates if called in the context of `_getBidAmount` in Escrow.sol (true) or not (false).
    function _updateAnalytics(
        EscrowAccountAccessData memory aData,
        uint256 gasUsed,
        bool solverWon,
        bool bidFind
    )
        internal
        pure
    {
        if (gasUsed > 0) aData.totalGasUsed += uint64(gasUsed / _GAS_USED_DECIMALS_TO_DROP);
        if (solverWon) {
            aData.auctionWins++;
        } else if (!bidFind) {
            aData.auctionFails++;
        }
    }
}
