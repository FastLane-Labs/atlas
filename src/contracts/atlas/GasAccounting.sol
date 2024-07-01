//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafetyLocks } from "src/contracts/atlas/SafetyLocks.sol";
import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";
import { AccountingMath } from "src/contracts/libraries/AccountingMath.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";

/// @title GasAccounting
/// @author FastLane Labs
/// @notice GasAccounting manages the accounting of gas surcharges and escrow balances for the Atlas protocol.
abstract contract GasAccounting is SafetyLocks {
    using EscrowBits for uint256;
    using AccountingMath for uint256;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        SafetyLocks(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    /// @notice Sets the initial accounting values for the metacall transaction.
    /// @param gasMarker The gas marker used to calculate the initial accounting values.
    function _initializeAccountingValues(uint256 gasMarker) internal {
        uint256 rawClaims = (FIXED_GAS_OFFSET + gasMarker) * tx.gasprice;

        // Set any withdraws or deposits
        claims = rawClaims.withBundlerSurcharge();
        fees = rawClaims.getAtlasSurcharge(); // Atlas surcharge is based on the raw claims value.
        deposits = msg.value;
        writeoffs = 0;
        withdrawals = 0;
    }

    /// @notice Contributes ETH to the contract, increasing the deposits if a non-zero value is sent.
    function contribute() external payable {
        address currentEnvironment = lock.activeEnvironment;
        if (currentEnvironment != msg.sender) revert InvalidExecutionEnvironment(currentEnvironment);
        _contribute();
    }

    /// @notice Borrows ETH from the contract, transferring the specified amount to the caller if available.
    /// @dev Borrowing is only available until the end of the SolverOperation phase, for solver protection.
    /// @param amount The amount of ETH to borrow.
    function borrow(uint256 amount) external payable {
        if (amount == 0) return;

        // borrow() can only be called by the Execution Environment (by delegatecalling a DAppControl hook), and only
        // during or before the SolverOperation phase.
        Lock memory _lock = lock;
        if (_lock.activeEnvironment != msg.sender) {
            revert InvalidExecutionEnvironment(_lock.activeEnvironment);
        }
        if (_lock.phase > uint8(ExecutionPhase.SolverOperation)) revert WrongPhase();

        // borrow() will revert if called after solver calls reconcile()
        (, bool calledBack,) = _solverLockData();
        if (calledBack) revert WrongPhase();

        if (_borrow(amount)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert InsufficientAtlETHBalance(address(this).balance, amount);
        }
    }

    /// @notice Calculates the current shortfall currently owed by the winning solver.
    /// @dev The shortfall is calculated `(claims + withdrawals + fees - writeoffs) - deposits`. If this value is less
    /// than zero, shortfall returns 0 as there is no shortfall because the solver is in surplus.
    /// @return The current shortfall amount, or 0 if there is no shortfall.
    function shortfall() external view returns (uint256) {
        uint256 deficit = claims + withdrawals + fees - writeoffs;
        uint256 _deposits = deposits;
        return (deficit > _deposits) ? (deficit - _deposits) : 0;
    }

    /// @notice Allows a solver to settle any outstanding ETH owed, either to repay gas used by their solverOp or to
    /// repay any ETH borrowed from Atlas. This debt can be paid either by sending ETH when calling this function
    /// (msg.value) or by approving Atlas to use a certain amount of the solver's bonded AtlETH.
    /// @param maxApprovedGasSpend The maximum amount of the solver's bonded AtlETH that Atlas can deduct to cover the
    /// solver's debt.
    /// @return owed The amount owed, if any, by the solver after reconciliation.
    function reconcile(uint256 maxApprovedGasSpend) external payable returns (uint256 owed) {
        // NOTE: maxApprovedGasSpend is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe. Assuming they're successful, a value up to this amount
        // will be subtracted from the solver's bonded AtlETH during _settle().

        // NOTE: After reconcile is called successfully by the solver, neither the claims nor
        // withdrawals values can be increased.

        // NOTE: While anyone can call this function, it can only be called in the SolverOperation phase. Because Atlas
        // calls directly to the solver contract in this phase, the solver should be careful to not call malicious
        // contracts which may call reconcile() on their behalf, with an excessive maxApprovedGasSpend.
        if (lock.phase != uint8(ExecutionPhase.SolverOperation)) revert WrongPhase();

        (address currentSolver, bool calledBack, bool fulfilled) = _solverLockData();
        uint256 bondedBalance = uint256(accessData[currentSolver].bonded);

        // Solver can only approve up to their bonded balance, not more
        if (maxApprovedGasSpend > bondedBalance) maxApprovedGasSpend = bondedBalance;

        uint256 _deductions = claims + withdrawals + fees - writeoffs;
        uint256 _additions = deposits + msg.value;

        // Add msg.value to solver's deposits
        // NOTE: Surplus deposits are credited back to the Solver during settlement.
        // NOTE: This function is called inside the solver try/catch and will be undone if solver fails.
        if (msg.value > 0) deposits = _additions;

        // CASE: Callback verified but insufficient balance
        if (_deductions > _additions + maxApprovedGasSpend) {
            if (!calledBack) {
                // Setting the solverLock here does not make the solver liable for the submitted maxApprovedGasSpend,
                // but it does treat any msg.value as a deposit and allows for either the solver to call back with a
                // higher maxApprovedGasSpend or to have their deficit covered by a contribute during the postSolverOp
                // hook.
                _solverLock = uint256(uint160(currentSolver)) | _SOLVER_CALLED_BACK_MASK;
            }
            return _deductions - _additions;
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
    /// @dev Borrowing should never be allowed after the SolverOperation phase, for solver safety. This is enforced in
    /// the external `borrow` function, and the only other time this internal `_borrow` function is called is in
    /// `_solverOpInner` which happens at the beginning of the SolverOperation phase.
    /// @param amount The amount of ETH to borrow.
    /// @return valid A boolean indicating whether the borrowing operation was successful.
    function _borrow(uint256 amount) internal returns (bool valid) {
        if (amount == 0) return true;
        if (address(this).balance < amount) return false;

        withdrawals += amount;

        return true;
    }

    /// @notice Takes AtlETH from the owner's bonded balance and, if necessary, from the owner's unbonding balance to
    /// increase transient solver deposits.
    /// @param owner The address of the owner from whom AtlETH is taken.
    /// @param amount The amount of AtlETH to be taken.
    /// @param solverWon A boolean indicating whether the solver won the bid.
    /// @return deficit The amount of AtlETH that was not repaid, if any.
    function _assign(address owner, uint256 amount, bool solverWon) internal returns (uint256 deficit) {
        if (amount > type(uint112).max) revert ValueTooLarge();
        uint112 amt = uint112(amount);

        EscrowAccountAccessData memory aData = accessData[owner];

        if (amt > aData.bonded) {
            // The bonded balance does not cover the amount owed. Check if there is enough unbonding balance to
            // make up for the missing difference. If not, there is a deficit. Atlas does not consider drawing from
            // the regular AtlETH balance (not bonded nor unbonding) to cover the remaining deficit because it is
            // not meant to be used within an Atlas transaction, and must remain independent.
            EscrowAccountBalance memory bData = _balanceOf[owner];

            if (amt > bData.unbonding + aData.bonded) {
                // The unbonding balance is insufficient to cover the remaining amount owed. There is a deficit. Set
                // both bonded and unbonding balances to 0 and adjust the "amount" variable to reflect the amount
                // that was actually deducted.
                uint256 total = uint256(bData.unbonding + aData.bonded); // contribute less to deposits ledger
                deficit = amount - total;
                _balanceOf[owner].unbonding = 0;
                aData.bonded = 0;

                writeoffs += deficit;
                amount -= deficit; // Set amount equal to total to accurately track the changing bondedTotalSupply
            } else {
                // The unbonding balance is sufficient to cover the remaining amount owed. Draw everything from the
                // bonded balance, and adjust the unbonding balance accordingly.
                _balanceOf[owner].unbonding = bData.unbonding + aData.bonded - amt;
                aData.bonded = 0;
            }
        } else {
            // The bonded balance is sufficient to cover the amount owed.
            aData.bonded -= amt;
        }

        // Update aData vars before persisting changes in accessData
        if (solverWon && deficit == 0) {
            unchecked {
                ++aData.auctionWins;
            }
        } else {
            unchecked {
                ++aData.auctionFails;
            }
        }
        aData.lastAccessedBlock = uint32(block.number);
        aData.totalGasUsed += uint64(amount / _GAS_USED_DECIMALS_TO_DROP);

        accessData[owner] = aData;

        bondedTotalSupply -= amount;
        deposits += amount;
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

        unchecked {
            ++aData.auctionWins;
        }

        accessData[owner] = aData;
        withdrawals += amount;
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
        uint256 gasUsed = (gasWaterMark + _SOLVER_BASE_GAS_USED - gasleft()) * tx.gasprice;

        if (includeCalldata) {
            gasUsed += _getCalldataCost(solverOp.data.length);
        }

        // Calculate what the solver owes
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        if (!result.updateEscrow()) {
            // CASE: Solver is not responsible for the failure of their operation, so we blame the bundler
            // and reduce the total amount refunded to the bundler
            writeoffs += gasUsed.withAtlasAndBundlerSurcharges();
        } else {
            // CASE: Solver failed, so we calculate what they owe.
            _assign(solverOp.from, gasUsed.withAtlasAndBundlerSurcharges(), false);
        }
    }

    /// @param ctx Context struct containing relavent context information for the Atlas auction.
    /// @param solverGasLimit The maximum gas limit for a solver, as set in the DAppConfig
    function _adjustAccountingForFees(
        Context memory ctx,
        uint256 solverGasLimit
    )
        internal
        returns (
            uint256 _withdrawals,
            uint256 _deposits,
            uint256 _claims,
            uint256 _writeoffs,
            uint256 netAtlasGasSurcharge
        )
    {
        uint256 _surcharge = cumulativeSurcharge;

        _claims = claims;
        _writeoffs = writeoffs;
        _withdrawals = withdrawals;
        _deposits = deposits;

        uint256 _gasLeft = gasleft(); // Hold this constant for the calculations

        // Estimate the unspent, remaining gas that the Solver will not be liable for.
        uint256 _gasRemainder = _gasLeft * tx.gasprice;

        // Calculate the preadjusted netAtlasGasSurcharge
        netAtlasGasSurcharge = fees - _gasRemainder.getAtlasSurcharge();

        _claims -= _gasRemainder.withBundlerSurcharge();
        _withdrawals += netAtlasGasSurcharge;
        cumulativeSurcharge = _surcharge + netAtlasGasSurcharge; // Update the cumulative surcharge

        // Calculate whether or not the bundler used an excessive amount of gas and, if so, reduce their
        // gas rebate. By reducing the _claims, solvers end up paying less in total.
        if (ctx.solverCount > 0) {
            // Calculate the unadjusted bundler gas surcharge
            uint256 _grossBundlerGasSurcharge = _claims.withoutBundlerSurcharge();

            // Calculate an estimate for how much gas should be remaining
            // NOTE: There is a free buffer of one SolverOperation because solverIndex starts at 0.
            uint256 _upperGasRemainingEstimate =
                (solverGasLimit * (ctx.solverCount - ctx.solverIndex)) + _BUNDLER_GAS_PENALTY_BUFFER;

            // Increase the _writeoffs value if the bundler set too high of a gas parameter and forced solvers to
            // maintain higher escrow balances.
            if (_gasLeft > _upperGasRemainingEstimate) {
                // Penalize the bundler's gas
                uint256 _bundlerGasOveragePenalty =
                    _grossBundlerGasSurcharge - (_grossBundlerGasSurcharge * _upperGasRemainingEstimate / _gasLeft);
                _writeoffs += _bundlerGasOveragePenalty;
            }
        }
    }

    /// @notice Settle makes the final adjustments to accounting variables based on gas used in the metacall. AtlETH is
    /// either taken (via _assign) or given (via _credit) to the winning solver, the bundler is sent the appropriate
    /// refund for gas spent, and Atlas' gas surcharge is updated.
    /// @param ctx Context struct containing relavent context information for the Atlas auction.
    /// @param solverGasLimit The dApp's maximum gas limit for a solver, as set in the DAppConfig.
    /// @return claimsPaidToBundler The amount of ETH paid to the bundler in this function.
    /// @return netAtlasGasSurcharge The net gas surcharge of the metacall, taken by Atlas.
    function _settle(
        Context memory ctx,
        uint256 solverGasLimit
    )
        internal
        returns (uint256 claimsPaidToBundler, uint256 netAtlasGasSurcharge)
    {
        // NOTE: If there is no winning solver but the dApp config allows unfulfilled 'successes', the bundler
        // is treated as the solver.

        // If a solver won, their address is still in the _solverLock
        address _winningSolver = address(uint160(_solverLock));

        // Load what we can from storage so that it shows up in the gasleft() calc

        uint256 _claims;
        uint256 _writeoffs;
        uint256 _withdrawals;
        uint256 _deposits;

        (_withdrawals, _deposits, _claims, _writeoffs, netAtlasGasSurcharge) =
            _adjustAccountingForFees(ctx, solverGasLimit);

        uint256 _amountSolverPays;
        uint256 _amountSolverReceives;

        // Calculate the balances that should be debited or credited to the solver and the bundler
        if (_deposits < _withdrawals) {
            _amountSolverPays = _withdrawals - _deposits;
        } else {
            _amountSolverReceives += (_deposits - _withdrawals);
        }

        // Only force solver to pay gas claims if they aren't also the bundler
        // NOTE: If the auction isn't won, _winningSolver will be address(0).
        if (ctx.solverSuccessful && _winningSolver != ctx.bundler) {
            _amountSolverPays += (_claims - _writeoffs);
            claimsPaidToBundler = (_claims - _writeoffs);
        } else {
            claimsPaidToBundler = 0;
            _winningSolver = ctx.bundler;
        }

        if (_amountSolverPays > _amountSolverReceives) {
            if (!ctx.solverSuccessful) {
                revert InsufficientTotalBalance(_amountSolverPays - _amountSolverReceives);
            } else {
                uint256 deficit = _assign(_winningSolver, _amountSolverPays - _amountSolverReceives, true);
                if (deficit > claimsPaidToBundler) revert InsufficientTotalBalance(deficit - claimsPaidToBundler);
                claimsPaidToBundler -= deficit;
            }
        } else {
            _credit(_winningSolver, _amountSolverReceives - _amountSolverPays);
        }

        if (claimsPaidToBundler != 0) SafeTransferLib.safeTransferETH(ctx.bundler, claimsPaidToBundler);

        return (claimsPaidToBundler, netAtlasGasSurcharge);
    }

    /// @notice Calculates the gas cost of the calldata used to execute a SolverOperation.
    /// @param calldataLength The length of the `data` field in the SolverOperation.
    /// @return calldataCost The gas cost of the calldata used to execute the SolverOperation.
    function _getCalldataCost(uint256 calldataLength) internal view returns (uint256 calldataCost) {
        // NOTE: Alter this for L2s.

        // _SOLVER_OP_BASE_CALLDATA = SolverOperation calldata length excluding solverOp.data
        calldataCost = (calldataLength + _SOLVER_OP_BASE_CALLDATA) * _CALLDATA_LENGTH_PREMIUM * tx.gasprice;
    }
}
