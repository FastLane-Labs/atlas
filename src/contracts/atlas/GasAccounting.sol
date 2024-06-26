//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafetyLocks } from "src/contracts/atlas/SafetyLocks.sol";
import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
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
        (, bool calledBack, bool fulfilled) = _solverLockData();
        if (calledBack || fulfilled) revert WrongPhase();

        if (_borrow(amount)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert InsufficientAtlETHBalance(address(this).balance, amount);
        }
    }

    /// @notice Calculates the current shortfall between deficit (claims + withdrawals) and deposits.
    /// @return The current shortfall amount, if any.
    function shortfall() external view returns (uint256) {
        uint256 deficit = claims + withdrawals - writeoffs;
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
        // to be used to cover what they owe. Assuming they're successful, a value up to this amount
        // will be subtracted from the solver's bonded AtlETH during _settle().

        // NOTE: After reconcile is called successfully by the solver, neither the claims nor
        // withdrawals values can be increased.

        uint256 bondedBalance = uint256(accessData[solverFrom].bonded);

        if (maxApprovedGasSpend > bondedBalance) maxApprovedGasSpend = bondedBalance;

        Lock memory _lock = lock;

        if (_lock.activeEnvironment != environment) {
            revert InvalidExecutionEnvironment(_lock.activeEnvironment);
        }
        if (_lock.phase != uint8(ExecutionPhase.SolverOperation)) {
            revert WrongPhase();
        }

        (address currentSolver, bool calledBack, bool fulfilled) = _solverLockData();

        if (solverFrom != currentSolver) revert InvalidSolverFrom(currentSolver);

        uint256 _deductions = claims + withdrawals - writeoffs;
        uint256 _additions = deposits + msg.value;

        // Add msg.value to solver's deposits
        // NOTE: This is inside the solver try/catch and will be undone if solver fails
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

                amount = total; // Set amount equal to total to accurately track the changing bondedTotalSupply
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

    /// @notice Releases the solver lock and adjusts the solver's escrow balance based on the gas used and other
    /// factors.
    /// @dev Calculates the gas used for the SolverOperation and adjusts the solver's escrow balance accordingly.
    /// @param solverOp The current SolverOperation for which to account
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

        gasUsed = gasUsed * (SURCHARGE_SCALE + ATLAS_SURCHARGE_RATE + BUNDLER_SURCHARGE_RATE) / SURCHARGE_SCALE;

        // Calculate what the solver owes
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        if (!result.updateEscrow()) {
            // CASE: Solver is not responsible for the failure of their operation, so we blame the bundler
            // and reduce the total amount refunded to the bundler
            writeoffs += gasUsed;
        } else {
            // CASE: Solver failed, so we calculate what they owe.
            uint256 deficit = _assign(solverOp.from, gasUsed, false);
            if (deficit > 0) {
                // Write off any deficit as a gas loss to the bundler so that other solvers aren't forced to pay it.
                writeoffs += deficit;
            }
        }
    }

    /// @param ctx Context struct containing relavent context information for the Atlas auction.
    /// @param solverGasLimit The maximum gas limit for a solver, as set in the DAppConfig
    function _getAdjustedClaimsAndWriteoffs(
        Context memory ctx,
        uint256 solverGasLimit
    )
        internal
        view
        returns (uint256 _claims, uint256 _writeoffs)
    {
        _claims = claims;
        _writeoffs = writeoffs;

        uint256 _gasLeft = gasleft(); // Hold this constant for the calculations

        uint256 _gasRemainder =
            _gasLeft * tx.gasprice * (SURCHARGE_SCALE + ATLAS_SURCHARGE_RATE + BUNDLER_SURCHARGE_RATE) / SURCHARGE_SCALE;
        _claims -= _gasRemainder;

        // By reducing the _claims, solvers end up paying less in total.
        if (ctx.solverCount > 0) {
            uint256 _bundlerGasOveragePenalty;

            // Calculate the unadjusted bundler gas surcharge
            uint256 _grossBundlerGasSurcharge =
                (_claims * BUNDLER_SURCHARGE_RATE) / (SURCHARGE_SCALE + ATLAS_SURCHARGE_RATE + BUNDLER_SURCHARGE_RATE);

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

    /// @notice Settles the transaction after execution, determining the final distribution of funds between the winning
    /// solver and the bundler based on the outcome.
    /// @dev This function adjusts the claims, withdrawals, deposits, and surcharges based on the gas used by the
    /// transaction.
    /// @param ctx Context struct containing relavent context information for the Atlas auction.
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
        uint256 _surcharge = cumulativeSurcharge;
        uint256 _withdrawals = withdrawals;
        uint256 _deposits = deposits;
        (uint256 _claims, uint256 _writeoffs) = _getAdjustedClaimsAndWriteoffs(ctx, solverGasLimit);

        netAtlasGasSurcharge =
            (_claims * ATLAS_SURCHARGE_RATE) / (SURCHARGE_SCALE + ATLAS_SURCHARGE_RATE + BUNDLER_SURCHARGE_RATE);

        // Update the stored cumulative surcharge
        cumulativeSurcharge = _surcharge + netAtlasGasSurcharge;

        // Handle the settlement accounting logs
        if (!ctx.solverSuccessful) {
            // CASE: No solver was successful

            // Ignore assigning to the winningSolver, just refund the bet deposits to the bundler if applicable
            if (_deposits < _withdrawals + netAtlasGasSurcharge) {
                // NOTE: We assume the bundler is fully on the hook for the gas, so we ignore claims and writeoffs
                // and focus exclusively on deposits and withdrawals.
                // The "+ netAtlasGasSurcharge" forces the bundler to pay the surcharge
                revert InsufficientTotalBalance(_withdrawals + netAtlasGasSurcharge - _deposits);
            }
            claimsPaidToBundler = _deposits - _withdrawals;
        } else if (_winningSolver == ctx.bundler) {
            // CASE: The winning solver is also the bundler
            if (_deposits < _withdrawals + netAtlasGasSurcharge) {
                // CASE: in deficit, subtract from bonded balance
                uint256 amountOwed = _withdrawals + netAtlasGasSurcharge - _deposits;
                uint256 deficit = _assign(_winningSolver, amountOwed, true);
                if (deficit > 0) {
                    revert InsufficientTotalBalance(deficit); // Revert if insufficient bonded balance.
                }
                claimsPaidToBundler = 0; // Bundler-Solver is in deficit, no need to pay them.
            } else {
                // CASE: in surplus, add to bonded balance by crediting the bundler at bottom of function
                claimsPaidToBundler = _deposits - _withdrawals - netAtlasGasSurcharge;
            }
        } else if (_writeoffs + _deposits < _claims + _withdrawals) {
            // CASE: Not a special bundler, solver successful, balance in deficit.
            // NOTE _claims and _writeoffs already have the Gas Surcharges factored in
            uint256 amountOwed = _claims + _withdrawals - _writeoffs - _deposits;
            uint256 deficit = _assign(_winningSolver, amountOwed, true);
            if (deficit > 0) {
                // CASE: Solver's bonded balance isn't enough to cover the amount owed, and the
                // winning solver is unrelated to the bundler. The bundler is not the solver.
                if (deficit > _claims - _writeoffs - netAtlasGasSurcharge) {
                    // CASE: The deficit is too large to writeoff by having the bundler absorb the cost
                    revert InsufficientTotalBalance(deficit);
                } else {
                    // CASE: We can writeoff the deficit (bundler has already paid the gas anyway)
                    // TODO: Ensure incentive compatibility
                    _writeoffs += deficit;
                }
            }
            claimsPaidToBundler = _claims - _writeoffs - netAtlasGasSurcharge;
        } else {
            // CASE: Solver is in surplus, add to bonded balance
            uint256 amountCredited = _deposits + _writeoffs - _claims - _withdrawals;
            _credit(_winningSolver, amountCredited);
            claimsPaidToBundler = _claims - _writeoffs - netAtlasGasSurcharge;
        }

        if (claimsPaidToBundler > 0) {
            if (msg.value == 0) {
                _credit(ctx.bundler, claimsPaidToBundler);
            } else if (msg.value < claimsPaidToBundler) {
                _credit(ctx.bundler, claimsPaidToBundler - msg.value);
                SafeTransferLib.safeTransferETH(ctx.bundler, msg.value);
            } else {
                SafeTransferLib.safeTransferETH(ctx.bundler, claimsPaidToBundler);
            }
        }

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
