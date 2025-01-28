//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { SafetyLocks } from "./SafetyLocks.sol";
import { EscrowBits } from "../libraries/EscrowBits.sol";
import { AccountingMath } from "../libraries/AccountingMath.sol";
import { GasAccLib, GasLedger, BorrowsLedger } from "../libraries/GasAccLib.sol";
import { SolverOperation } from "../types/SolverOperation.sol";
import { DAppConfig } from "../types/ConfigTypes.sol";
import { IL2GasCalculator } from "../interfaces/IL2GasCalculator.sol";
import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

/// @title GasAccounting
/// @author FastLane Labs
/// @notice GasAccounting manages the accounting of gas surcharges and escrow balances for the Atlas protocol.
abstract contract GasAccounting is SafetyLocks {
    using EscrowBits for uint256;
    using AccountingMath for uint256;
    using GasAccLib for GasLedger;
    using GasAccLib for BorrowsLedger;

    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        uint256 bundlerSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator
    )
        SafetyLocks(
            escrowDuration,
            atlasSurchargeRate,
            bundlerSurchargeRate,
            verification,
            simulator,
            initialSurchargeRecipient,
            l2GasCalculator
        )
    { }

    /// @notice Sets the initial gas accounting values for the metacall transaction.
    /// @param gasMarker The gasMarker measurement at the start of the metacall, which includes Execution gas limits,
    /// Calldata gas costs, and an additional buffer for safety.
    function _initializeAccountingValues(uint256 gasMarker) internal {
        (uint256 _atlasSurchargeRate, uint256 _bundlerSurchargeRate) = _surchargeRates();
        uint256 _rawClaims = gasMarker * tx.gasprice;

        t_gasLedger = GasLedger({
            totalMetacallGas: uint64(gasMarker), // TODO cleaner cast or arg starts as uint64
            solverFaultFailureGas: 0,
            unreachedSolverGas: 123, // TODO get this
            maxApprovedGasSpend: 0
        }).pack();

        t_borrowsLedger = BorrowsLedger({
            borrows: 0,
            repays: uint128(msg.value)
        }).pack();

        // The 3 components of gas cost charged to solvers are:
        // - Base gas cost (g)
        // - Atlas gas surcharge (A)
        // - Bundler gas surcharge (B)
        // = g + A + B

        // Claims records the g + B portions of gas charge
        t_claims = _rawClaims.withSurcharge(_bundlerSurchargeRate);

        // Fees records only the A portion of gas charge
        t_fees = _rawClaims.getSurcharge(_atlasSurchargeRate);

        // If any native token sent in the metacall, add to the repays account
        t_repays = msg.value;

        // Explicitly set other transient vars to 0 in case multiple metacalls in single tx.
        t_writeoffs = 0;
        t_borrows = 0;
        t_solverSurcharge = 0;
        t_solverLock = 0;
        t_solverTo = address(0);

        // The Lock slot is cleared at the end of the metacall, so no need to zero again here.
    }

    /// @notice Contributes ETH to the contract, increasing the deposits if a non-zero value is sent.
    function contribute() external payable {
        address _activeEnv = _activeEnvironment();
        if (_activeEnv != msg.sender) revert InvalidExecutionEnvironment(_activeEnv);
        _contribute();
    }

    /// @notice Borrows ETH from the contract, transferring the specified amount to the caller if available.
    /// @dev Borrowing is only available until the end of the SolverOperation phase, for solver protection.
    /// @param amount The amount of ETH to borrow.
    function borrow(uint256 amount) external payable {
        if (amount == 0) return;

        // borrow() can only be called by the Execution Environment (by delegatecalling a DAppControl hook), and only
        // during or before the SolverOperation phase.
        (address _activeEnv,, uint8 _currentPhase) = _lock();
        if (_activeEnv != msg.sender) revert InvalidExecutionEnvironment(_activeEnv);
        if (_currentPhase > uint8(ExecutionPhase.SolverOperation)) revert WrongPhase();

        // borrow() will revert if called after solver calls reconcile()
        (, bool _calledBack,) = _solverLockData();
        if (_calledBack) revert WrongPhase();

        if (_borrow(amount)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert InsufficientAtlETHBalance(address(this).balance, amount);
        }
    }

    /// @notice Calculates the current shortfall currently owed by the winning solver.
    /// @dev The shortfall is calculated `(claims + withdrawals + fees - writeoffs) - deposits`. If this value is less
    /// than zero, shortfall returns 0 as there is no shortfall because the solver is in surplus.
    /// @return gasLiability The total gas charge (base + surcharges) owed by the solver. Can be repaid using bonded
    /// balance or native token.
    /// @return borrowLiability The total value of ETH borrowed but not yet repaid, only repayable using native token.
    function shortfall() external view returns (uint256 gasLiability, uint256 borrowLiability) {
        gasLiability = t_claims + t_fees - t_writeoffs - t_deposits;
        borrowLiability = (t_borrows < t_repays) ? 0 : t_borrows - t_repays;
    }

    // TODO rework comments and logic in gas acc refactor
    function _gasDeficit() internal view returns (uint256) {
        // _deficit() is compared against t_deposits which includes:
        // + msg.value deposited
        // + gas cost + A + B (prev solver fault fails)

        // _deficit() is therefore composed of:
        // + withdrawals = msg.value borrowed
        // + claims = gas cost + B (full tx)
        // + fees = A (full tx)
        // - writeoffs = gas cost + A + B (prev bundler fault fails)

        // Such that `deficit() - t_deposits` =
        // + msg.value still owed
        // + gas cost + A + B (full tx)
        // - gas cost + A + B (prev solver fault fails)
        // - gas cost + A + B (prev bundler fault fails)
        // == only what the current solver owes if they win

        // NOTE: Above is outdated. This is gas deficit only. Not borrow-repay deficit
        return t_claims + t_fees - t_writeoffs;
    }

    /// @notice Allows a solver to settle any outstanding ETH owed, either to repay gas used by their solverOp or to
    /// repay any ETH borrowed from Atlas. This debt can be paid either by sending ETH when calling this function
    /// (msg.value) or by approving Atlas to use a certain amount of the solver's bonded AtlETH.
    /// @param maxApprovedGasSpend The maximum amount of the solver's bonded AtlETH that Atlas can deduct to cover the
    /// solver's debt.
    /// @return owed The amount owed, if any, by the solver after reconciliation.
    /// @dev The solver can call this function multiple times until the owed amount is zero.
    /// @dev Note: `reconcile()` must be called by the solver to avoid a `CallbackNotCalled` error in `solverCall()`.
    function reconcile(uint256 maxApprovedGasSpend) external payable returns (uint256 owed) {
        // NOTE: maxApprovedGasSpend is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe. Assuming they're successful, a value up to this amount
        // will be subtracted from the solver's bonded AtlETH during _settle().

        // NOTE: After reconcile is called for the first time by the solver, neither the claims nor the borrows values
        // can be increased.

        // NOTE: While anyone can call this function, it can only be called in the SolverOperation phase. Because Atlas
        // calls directly to the solver contract in this phase, the solver should be careful to not call malicious
        // contracts which may call reconcile() on their behalf, with an excessive maxApprovedGasSpend.
        if (_phase() != uint8(ExecutionPhase.SolverOperation)) revert WrongPhase();
        if (msg.sender != t_solverTo) revert InvalidAccess();

        (address _currentSolver, bool _calledBack,) = _solverLockData();
        uint256 _bondedBalance = uint256(S_accessData[_currentSolver].bonded);

        // Solver can only approve up to their bonded balance, not more
        if (maxApprovedGasSpend > _bondedBalance) maxApprovedGasSpend = _bondedBalance;

        // Store solver's maxApprovedGasSpend for use in the _isBalanceReconciled() check
        t_maxApprovedGasSpend = maxApprovedGasSpend;

        uint256 _borrows = t_borrows; // total native borrows
        uint256 _repays = t_repays; // total native repayments of borrows
        uint256 _maxGasLiability = _gasDeficit(); // max gas liability of winning solver

        if (msg.value > 0) {
            _repays += msg.value;
            t_repays = _repays;
        }

        // Check if fullfilled:
        // - native borrows must be repaid (using only native token)
        // - gas liabilities must be repaid (using bonded AtlETH or native token)

        if (_borrows > _repays) {
            if (!_calledBack) t_solverLock = (uint256(uint160(_currentSolver)) | _SOLVER_CALLED_BACK_MASK);
            return _maxGasLiability + (_borrows - _repays);
        } else {
            uint256 _excess = _repays - _borrows;
            if (maxApprovedGasSpend + _excess < _maxGasLiability) {
                if (!_calledBack) t_solverLock = (uint256(uint160(_currentSolver)) | _SOLVER_CALLED_BACK_MASK);
                return _maxGasLiability - _excess;
            }
        }

        // If we get here, native borrows have been repaid, and enough approved to cover gas liabilities
        t_solverLock = (uint256(uint160(_currentSolver)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK);
        return 0;
    }

    /// @notice Internal function to handle ETH contribution, increasing deposits if a non-zero value is sent.
    function _contribute() internal {
        if (msg.value != 0) t_repays += msg.value;
    }

    /// @notice Borrows ETH from the contract, transferring the specified amount to the caller if available.
    /// @dev Borrowing should never be allowed after the SolverOperation phase, for solver safety. This is enforced in
    /// the external `borrow` function, and the only other time this internal `_borrow` function is called is in
    /// `_solverOpInner` which happens at the beginning of the SolverOperation phase.
    /// @param amount The amount of ETH to borrow.
    /// @return valid A boolean indicating whether the borrowing operation was successful.
    function _borrow(uint256 amount) internal returns (bool valid) {
        if (amount == 0) return true;
        if (address(this).balance < amount) return false;

        t_borrows += amount;

        return true;
    }

    /// @notice Takes AtlETH from the owner's bonded balance and, if necessary, from the owner's unbonding balance to
    /// increase transient solver deposits.
    /// @param account The address of the account from which AtlETH is taken.
    /// @param amount The amount of AtlETH to be taken.
    /// @return deficit The amount of AtlETH that was not repaid, if any.
    function _assign(
        EscrowAccountAccessData memory accountData,
        address account,
        uint256 amount
    )
        internal
        returns (uint256 deficit)
    {
        uint112 _amt = SafeCast.toUint112(amount);

        // EscrowAccountAccessData memory _aData = S_accessData[account];

        if (_amt > accountData.bonded) {
            // The bonded balance does not cover the amount owed. Check if there is enough unbonding balance to
            // make up for the missing difference. If not, there is a deficit. Atlas does not consider drawing from
            // the regular AtlETH balance (not bonded nor unbonding) to cover the remaining deficit because it is
            // not meant to be used within an Atlas transaction, and must remain independent.

            EscrowAccountBalance memory _bData = s_balanceOf[account];
            uint256 _total = uint256(_bData.unbonding) + uint256(accountData.bonded);

            if (_amt > _total) {
                // The unbonding balance is insufficient to cover the remaining amount owed. There is a deficit. Set
                // both bonded and unbonding balances to 0 and adjust the "amount" variable to reflect the amount
                // that was actually deducted.
                deficit = amount - _total;
                s_balanceOf[account].unbonding = 0;
                accountData.bonded = 0;

                t_writeoffs += deficit;
                amount -= deficit; // Set amount equal to total to accurately track the changing bondedTotalSupply
            } else {
                // The unbonding balance is sufficient to cover the remaining amount owed. Draw everything from the
                // bonded balance, and adjust the unbonding balance accordingly.
                s_balanceOf[account].unbonding = SafeCast.toUint112(_total - _amt);
                accountData.bonded = 0;
            }
        } else {
            // The bonded balance is sufficient to cover the amount owed.
            accountData.bonded -= _amt;
        }

        // update lastAccessedBlock since balance is decreasing
        accountData.lastAccessedBlock = uint32(block.number);

        // NOTE: accountData changes must be persisted to storage separately

        S_bondedTotalSupply -= amount;
        t_deposits += amount;
    }

    /// @notice Increases the owner's bonded balance by the specified amount.
    /// @param accountData The EscrowAccountAccessData memory struct of the account being credited.
    /// @param amount The amount by which to increase the owner's bonded balance.
    function _credit(EscrowAccountAccessData memory accountData, uint256 amount) internal {
        accountData.bonded += SafeCast.toUint112(amount);
        S_bondedTotalSupply += amount;
        // NOTE: accountData changes must be persisted to storage separately
    }

    /// @notice Accounts for the gas cost of a failed SolverOperation, either by increasing writeoffs (if the bundler is
    /// blamed for the failure) or by assigning the gas cost to the solver's bonded AtlETH balance (if the solver is
    /// blamed for the failure).
    /// @param solverOp The current SolverOperation for which to account.
    /// @param gasWaterMark The `gasleft()` watermark taken at the start of executing the SolverOperation.
    /// @param result The result bitmap of the SolverOperation execution.
    /// @param includeCalldata Whether to include calldata cost in the gas calculation.
    function _handleSolverAccounting(
        SolverOperation calldata solverOp,
        uint256 gasWaterMark,
        uint256 result,
        bool includeCalldata
    )
        internal
    {
        uint256 _gasUsed = (gasWaterMark + _SOLVER_BASE_GAS_USED - gasleft()) * tx.gasprice;
        (uint256 _atlasSurchargeRate, uint256 _bundlerSurchargeRate) = _surchargeRates();

        if (includeCalldata) {
            _gasUsed += _getCalldataCost(solverOp.data.length);
        }

        // Calculate what the solver owes
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        if (result.bundlersFault()) {
            // CASE: Solver is not responsible for the failure of their operation, so we blame the bundler
            // and reduce the total amount refunded to the bundler
            t_writeoffs += _gasUsed.withSurcharges(_atlasSurchargeRate, _bundlerSurchargeRate);
        } else {
            // CASE: Solver failed, so we calculate what they owe.
            uint256 _gasUsedWithSurcharges = _gasUsed.withSurcharges(_atlasSurchargeRate, _bundlerSurchargeRate);
            uint256 _surchargesOnly = _gasUsedWithSurcharges - _gasUsed;

            EscrowAccountAccessData memory _solverAccountData = S_accessData[solverOp.from];

            // In `_assign()`, the failing solver's bonded AtlETH balance is reduced by `_gasUsedWithSurcharges`. Any
            // deficit from that operation is added to `writeoffs` and returned as `_assignDeficit` below. The portion
            // that can be covered by the solver's AtlETH is added to `deposits`, to account that it has been paid.
            uint256 _assignDeficit = _assign(_solverAccountData, solverOp.from, _gasUsedWithSurcharges);

            // Solver's analytics updated:
            // - increment auctionFails
            // - increase totalGasValueUsed by gas cost + surcharges paid by solver, less any deficit
            _updateAnalytics(_solverAccountData, false, _gasUsedWithSurcharges - _assignDeficit);

            // Persist the updated solver account data to storage
            S_accessData[solverOp.from] = _solverAccountData;

            // We track the surcharges (in excess of deficit - so the actual AtlETH that can be collected) separately,
            // so that in the event of no successful solvers, any `_assign()`ed surcharges can be attributed to an
            // increase in Atlas' cumulative surcharge.
            if (_surchargesOnly > _assignDeficit) {
                t_solverSurcharge += (_surchargesOnly - _assignDeficit);
            }
        }
    }

    function _writeOffBidFindGasCost(uint256 gasUsed) internal {
        (uint256 _atlasSurchargeRate, uint256 _bundlerSurchargeRate) = _surchargeRates();
        t_writeoffs += gasUsed.withSurcharges(_atlasSurchargeRate, _bundlerSurchargeRate);
    }

    /// @param ctx Context struct containing relevant context information for the Atlas auction.
    /// @return adjustedBorrows Borrows of the current metacall, adjusted by adding the Atlas gas surcharge.
    /// @return adjustedClaims Claims of the current metacall, adjusted by subtracting the unused gas scaled to include
    /// bundler surcharge.
    /// @return adjustedWriteoffs Writeoffs of the current metacall, adjusted by adding the bundler gas overage penalty
    /// if applicable.
    /// @return netAtlasGasSurcharge The net gas surcharge of the metacall, taken by Atlas.
    /// @dev This function is called internally to adjust the accounting for fees based on the gas usage.
    /// Note: The behavior of this function depends on whether `_bidFindingIteration()` or `_bidKnownIteration()` is
    /// used, as they both use a different order of execution.
    function _adjustAccountingForFees(Context memory ctx)
        internal
        returns (
            uint256 adjustedBorrows,
            uint256 adjustedClaims,
            uint256 adjustedWriteoffs,
            uint256 netAtlasGasSurcharge
        )
    {
        uint256 _surcharge = S_cumulativeSurcharge;

        adjustedBorrows = t_borrows;
        adjustedClaims = t_claims;
        adjustedWriteoffs = t_writeoffs;
        uint256 _fees = t_fees;
        (uint256 _atlasSurchargeRate, uint256 _bundlerSurchargeRate) = _surchargeRates();

        uint256 _gasLeft = gasleft(); // Hold this constant for the calculations

        // Estimate the unspent, remaining gas that the Solver will not be liable for.
        uint256 _gasRemainder = _gasLeft * tx.gasprice;

        adjustedClaims -= _gasRemainder.withSurcharge(_bundlerSurchargeRate);

        if (ctx.solverSuccessful) {
            // If a solver was successful, calc the full Atlas gas surcharge on the gas cost of the entire metacall, and
            // add it to withdrawals so that the cost is assigned to winning solver by the end of _settle(). This will
            // be offset by any gas surcharge paid by failed solvers, which would have been added to deposits or
            // writeoffs in _handleSolverAccounting(). As such, the winning solver does not pay for surcharge on the gas
            // used by other solvers.
            netAtlasGasSurcharge = _fees - _gasRemainder.getSurcharge(_atlasSurchargeRate);
            adjustedBorrows += netAtlasGasSurcharge;
            S_cumulativeSurcharge = _surcharge + netAtlasGasSurcharge;
        } else {
            // If no successful solvers, only collect partial surcharges from solver's fault failures (if any)
            uint256 _solverSurcharge = t_solverSurcharge;
            if (_solverSurcharge > 0) {
                netAtlasGasSurcharge = _solverSurcharge.getPortionFromTotalSurcharge({
                    targetSurchargeRate: _atlasSurchargeRate,
                    totalSurchargeRate: _atlasSurchargeRate + _bundlerSurchargeRate
                });

                // When no winning solvers, bundler max refund is 80% of metacall gas cost. The remaining 20% can be
                // collected through storage refunds. Any excess bundler surcharge is instead taken as Atlas surcharge.
                uint256 _bundlerSurcharge = _solverSurcharge - netAtlasGasSurcharge;
                uint256 _maxBundlerRefund = adjustedClaims.withoutSurcharge(_bundlerSurchargeRate).maxBundlerRefund();
                if (_bundlerSurcharge > _maxBundlerRefund) {
                    netAtlasGasSurcharge += _bundlerSurcharge - _maxBundlerRefund;
                }

                adjustedBorrows += netAtlasGasSurcharge;
                S_cumulativeSurcharge = _surcharge + netAtlasGasSurcharge;
            }
        }

        return (adjustedBorrows, adjustedClaims, adjustedWriteoffs, netAtlasGasSurcharge);
    }

    /// @notice Settle makes the final adjustments to accounting variables based on gas used in the metacall. AtlETH is
    /// either taken (via _assign) or given (via _credit) to the winning solver, the bundler is sent the appropriate
    /// refund for gas spent, and Atlas' gas surcharge is updated.
    /// @param ctx Context struct containing relevant context information for the Atlas auction.
    /// @param gasRefundBeneficiary The address to receive the gas refund.
    /// @return claimsPaidToBundler The amount of ETH paid to the bundler in this function.
    /// @return netAtlasGasSurcharge The net gas surcharge of the metacall, taken by Atlas.
    function _settle(
        Context memory ctx,
        address gasRefundBeneficiary
    )
        internal
        returns (uint256 claimsPaidToBundler, uint256 netAtlasGasSurcharge)
    {
        // NOTE: If there is no winning solver but the dApp config allows unfulfilled 'successes', the bundler
        // is treated as the solver.

        // If a solver won, their address is still in the _solverLock
        (address _winningSolver,,) = _solverLockData();

        if (gasRefundBeneficiary == address(0)) gasRefundBeneficiary = ctx.bundler;

        // Load what we can from storage so that it shows up in the gasleft() calc

        uint256 _claims;
        uint256 _writeoffs;
        uint256 _borrows;
        uint256 _deposits = t_deposits; // load here, not used in adjustment function below

        (_borrows, _claims, _writeoffs, netAtlasGasSurcharge) = _adjustAccountingForFees(ctx);

        uint256 _amountSolverPays;
        uint256 _amountSolverReceives;
        uint256 _adjustedClaims = _claims - _writeoffs;

        // Calculate the balances that should be debited or credited to the solver and the bundler
        if (_deposits < _borrows) {
            _amountSolverPays = _borrows - _deposits;
        } else {
            _amountSolverReceives = _deposits - _borrows;
        }

        // Only force solver to pay gas claims if they aren't also the bundler
        // NOTE: If the auction isn't won, _winningSolver will be address(0).
        if (ctx.solverSuccessful && _winningSolver != ctx.bundler) {
            _amountSolverPays += _adjustedClaims;
            claimsPaidToBundler = _adjustedClaims;
        } else if (_winningSolver == ctx.bundler) {
            claimsPaidToBundler = 0;
        } else {
            // this else block is only executed if there is no successful solver
            claimsPaidToBundler = 0;
            _winningSolver = gasRefundBeneficiary;
        }

        // Load winning solver's bonded/lastAccessedBlock/analytics data into memory
        EscrowAccountAccessData memory _winningSolverData = S_accessData[_winningSolver];

        if (_amountSolverPays > _amountSolverReceives) {
            if (!ctx.solverSuccessful) {
                revert InsufficientTotalBalance(_amountSolverPays - _amountSolverReceives);
            }

            uint256 _currentDeficit =
                _assign(_winningSolverData, _winningSolver, _amountSolverPays - _amountSolverReceives);
            if (_currentDeficit > claimsPaidToBundler) {
                revert InsufficientTotalBalance(_currentDeficit - claimsPaidToBundler);
            }
            claimsPaidToBundler -= _currentDeficit;
        } else {
            _credit(_winningSolverData, _amountSolverReceives - _amountSolverPays);
        }

        // Update analytics for the winning solver
        // If no winning solver, all analytics updates have already been made in _handleSolverAccounting()
        if (ctx.solverSuccessful) _updateAnalytics(_winningSolverData, true, _adjustedClaims);

        // Persist changes to winning solver's data back to storage
        S_accessData[_winningSolver] = _winningSolverData;

        // Set lock to FullyLocked to prevent any reentrancy possibility
        _setLockPhase(uint8(ExecutionPhase.FullyLocked));

        if (claimsPaidToBundler != 0) SafeTransferLib.safeTransferETH(gasRefundBeneficiary, claimsPaidToBundler);

        return (claimsPaidToBundler, netAtlasGasSurcharge);
    }

    /// @notice Updates auctionWins, auctionFails, and totalGasUsed values of a solver's EscrowAccountAccessData.
    /// @dev This function is only ever called in the context of bidFind = false so no risk of doublecounting changes.
    /// @param aData The Solver's EscrowAccountAccessData struct to update.
    /// @param auctionWon A boolean indicating whether the solver's solverOp won the auction.
    /// @param gasValueUsed The ETH value of gas used by the solverOp. Should be calculated as gasUsed * tx.gasprice.
    function _updateAnalytics(
        EscrowAccountAccessData memory aData,
        bool auctionWon,
        uint256 gasValueUsed
    )
        internal
        pure
    {
        if (auctionWon) {
            unchecked {
                ++aData.auctionWins;
            }
        } else {
            unchecked {
                ++aData.auctionFails;
            }
        }

        // Track total ETH value of gas spent by solver in metacalls. Measured in gwei (1e9 digits truncated).
        aData.totalGasValueUsed += SafeCast.toUint64(gasValueUsed / _GAS_VALUE_DECIMALS_TO_DROP);
    }

    /// @notice Calculates the gas cost of the calldata used to execute a SolverOperation.
    /// @param calldataLength The length of the `data` field in the SolverOperation.
    /// @return calldataCost The gas cost of the calldata used to execute the SolverOperation.
    function _getCalldataCost(uint256 calldataLength) internal view returns (uint256 calldataCost) {
        if (L2_GAS_CALCULATOR == address(0)) {
            // Default to using mainnet gas calculations
            // _SOLVER_OP_BASE_CALLDATA = SolverOperation calldata length excluding solverOp.data
            calldataCost = (calldataLength + _SOLVER_OP_BASE_CALLDATA) * _CALLDATA_LENGTH_PREMIUM_HALVED * tx.gasprice;
        } else {
            calldataCost =
                IL2GasCalculator(L2_GAS_CALCULATOR).getCalldataCost(calldataLength + _SOLVER_OP_BASE_CALLDATA);
        }
    }

    /// @notice Checks all obligations have been reconciled: native borrows AND gas liabilities.
    /// @return True if both dimensions are reconciled, false otherwise.
    function _isBalanceReconciled() internal view returns (bool) {
        return t_repays >= t_borrows && t_deposits + t_maxApprovedGasSpend >= _gasDeficit();
    }
}
