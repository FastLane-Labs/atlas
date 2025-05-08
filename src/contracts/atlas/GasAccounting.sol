//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { SafetyLocks } from "./SafetyLocks.sol";
import { EscrowBits } from "../libraries/EscrowBits.sol";
import { CallBits } from "../libraries/CallBits.sol";
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
    using CallBits for uint32;
    using AccountingMath for uint256;
    using SafeCast for uint256;
    using GasAccLib for uint256;
    using GasAccLib for GasLedger;
    using GasAccLib for BorrowsLedger;
    using FixedPointMathLib for uint256;

    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator
    )
        SafetyLocks(escrowDuration, atlasSurchargeRate, verification, simulator, initialSurchargeRecipient, l2GasCalculator)
    { }

    /// @notice Sets the initial gas accounting values for the metacall transaction in transient storage.
    /// @dev Resets `t_gasLedger`, `t_borrowsLedger`, `t_solverLock`, and `t_solverTo` at the start of each metacall.
    ///     Initializes `remainingMaxGas` with the overall gas estimate and `unreachedSolverGas` with the precalculated
    ///     gas for all potential solver operations. Sets initial `repays` based on `msg.value`.
    /// @param initialRemainingMaxGas The gas measurement at the start of the metacall, which generally includes
    ///     Execution gas limits, Calldata gas costs, and an additional buffer for safety. NOTE: If in exPostBids mode,
    ///     this param does not include calldata gas as solvers are not liable for calldata gas costs. And in
    ///     multipleSuccessfulSolvers mode, this param is the same value as `allSolverOpsGas`, because solvers are only
    ///     liable for their own solverOp gas, even if they execute successfully.
    /// @param allSolverOpsGas The sum of (C + E) gas limits for all solverOps in the metacall.
    function _initializeAccountingValues(
        uint256 initialRemainingMaxGas,
        uint256 allSolverOpsGas,
        uint24 bundlerSurchargeRate
    )
        internal
    {
        t_gasLedger = GasLedger({
            remainingMaxGas: initialRemainingMaxGas.toUint40(),
            writeoffsGas: 0,
            solverFaultFailureGas: 0,
            unreachedSolverGas: allSolverOpsGas.toUint40(),
            maxApprovedGasSpend: 0,
            atlasSurchargeRate: _atlasSurchargeRate(),
            bundlerSurchargeRate: bundlerSurchargeRate
        }).pack();

        // If any native token sent in the metacall, add to the repays account
        t_borrowsLedger = BorrowsLedger({ borrows: 0, repays: uint128(msg.value) }).pack();

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
    function borrow(uint256 amount) external {
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
        gasLiability = t_gasLedger.toGasLedger().solverGasLiability();

        BorrowsLedger memory _bL = t_borrowsLedger.toBorrowsLedger();
        borrowLiability = (_bL.borrows < _bL.repays) ? 0 : _bL.borrows - _bL.repays;
    }

    /// @notice Allows a solver to settle any outstanding ETH owed, either to repay gas used by their solverOp or to
    /// repay any ETH borrowed from Atlas. This debt can be paid either by sending ETH when calling this function
    /// (msg.value) or by approving Atlas to use a certain amount of the solver's bonded AtlETH.
    /// @param maxApprovedGasSpend The maximum amount of the solver's bonded AtlETH that Atlas can deduct to cover the
    /// solver's debt.
    /// @return owed The gas and borrow liability owed by the solver. The full gasLiability + borrowLiability amount is
    /// returned, unless the fulfilled, in which case 0 is returned.
    /// @dev The solver can call this function multiple times until the owed amount is zero.
    /// @dev Note: `reconcile()` must be called by the solver to avoid a `CallbackNotCalled` error in `solverCall()`.
    function reconcile(uint256 maxApprovedGasSpend) external payable returns (uint256 owed) {
        // NOTE: maxApprovedGasSpend is the amount of the solver's atlETH that the solver is allowing
        // to be used to cover what they owe. Assuming they're successful, a value up to this amount
        // will be subtracted from the solver's bonded AtlETH during _settle().

        // NOTE: After reconcile is called for the first time by the solver, neither the claims nor the borrows values
        // can be increased.

        (, uint32 _callConfig, uint8 _currentPhase) = _lock();

        // NOTE: While anyone can call this function, it can only be called in the SolverOperation phase. Because Atlas
        // calls directly to the solver contract in this phase, the solver should be careful to not call malicious
        // contracts which may call reconcile() on their behalf, with an excessive maxApprovedGasSpend.
        if (_currentPhase != uint8(ExecutionPhase.SolverOperation)) revert WrongPhase();
        if (msg.sender != t_solverTo) revert InvalidAccess();

        (address _currentSolver, bool _calledBack,) = _solverLockData();
        uint256 _bondedBalance = uint256(S_accessData[_currentSolver].bonded);

        // Solver can only approve up to their bonded balance, not more
        if (maxApprovedGasSpend > _bondedBalance) maxApprovedGasSpend = _bondedBalance;

        GasLedger memory _gL = t_gasLedger.toGasLedger();
        BorrowsLedger memory _bL = t_borrowsLedger.toBorrowsLedger();

        uint256 _borrows = _bL.borrows; // total native borrows
        uint256 _repays = _bL.repays; // total native repayments of borrows
        uint256 _maxGasLiability = _gL.solverGasLiability(); // max gas liability of winning solver

        // Store update to repays in t_borrowLedger, if any msg.value sent
        if (msg.value > 0) {
            _repays += msg.value;
            _bL.repays = _repays.toUint128();
            t_borrowsLedger = _bL.pack();
        }

        // Store solver's maxApprovedGasSpend for use in the _isBalanceReconciled() check
        if (maxApprovedGasSpend > 0) {
            // Convert maxApprovedGasSpend from wei (native token) units to gas units
            _gL.maxApprovedGasSpend = (maxApprovedGasSpend / tx.gasprice).toUint40();
            t_gasLedger = _gL.pack();
        }

        // Check if fullfilled:
        // - native borrows must be repaid (using only native token)
        // - gas liabilities must be repaid (using bonded AtlETH or native token)

        if (_borrows > _repays) {
            if (!_calledBack) t_solverLock = (uint256(uint160(_currentSolver)) | _SOLVER_CALLED_BACK_MASK);
            return _maxGasLiability + (_borrows - _repays);
        } else {
            // If multipleSuccessfulSolvers = true, the solver's gas liability cannot be paid in ETH - must be fully
            // paid by the solver's bonded AtlETH balance.
            uint256 _excess;
            if (!_callConfig.multipleSuccessfulSolvers()) _excess = _repays - _borrows;

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
        if (msg.value == 0) return;

        BorrowsLedger memory _bL = t_borrowsLedger.toBorrowsLedger();
        _bL.repays += msg.value.toUint128();
        t_borrowsLedger = _bL.pack();
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

        BorrowsLedger memory _bL = t_borrowsLedger.toBorrowsLedger();
        _bL.borrows += amount.toUint128();
        t_borrowsLedger = _bL.pack();

        return true;
    }

    /// @notice Takes AtlETH from the owner's bonded balance and, if necessary, from the owner's unbonding balance.
    /// @dev No GasLedger accounting changes are made in this function - should be done separately.
    /// @param accountData The EscrowAccountAccessData memory struct of the account being charged.
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
        uint112 _amt = amount.toUint112();

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
                amount -= deficit; // Set amount equal to total to accurately track the changing bondedTotalSupply
            } else {
                // The unbonding balance is sufficient to cover the remaining amount owed. Draw everything from the
                // bonded balance, and adjust the unbonding balance accordingly.
                s_balanceOf[account].unbonding = _total.toUint112() - _amt;
                accountData.bonded = 0;
            }
        } else {
            // The bonded balance is sufficient to cover the amount owed.
            accountData.bonded -= _amt;
        }

        S_bondedTotalSupply -= amount;

        // update lastAccessedBlock since bonded balance is decreasing
        accountData.lastAccessedBlock = uint32(block.number);
        // NOTE: accountData changes must be persisted to storage separately
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
    /// @param dConfigSolverGasLimit The gas limit for the solver operation, as specified in the DAppConfig.
    /// @param gasWaterMark The `gasleft()` watermark taken at the start of executing the SolverOperation.
    /// @param result The result bitmap of the SolverOperation execution.
    /// @param exPostBids A boolean indicating whether exPostBids is set to true in the current metacall.
    function _handleSolverFailAccounting(
        SolverOperation calldata solverOp,
        uint256 dConfigSolverGasLimit,
        uint256 gasWaterMark,
        uint256 result,
        bool exPostBids
    )
        internal
    {
        GasLedger memory _gL = t_gasLedger.toGasLedger();

        // Solvers do not pay for calldata gas in exPostBids mode.
        uint256 _calldataGas;
        if (!exPostBids) {
            _calldataGas = GasAccLib.solverOpCalldataGas(solverOp.data.length, L2_GAS_CALCULATOR);
        }

        // Solver execution max gas is calculated as solverOp.gas, with a ceiling of dConfig.solverGasLimit
        uint256 _executionMaxGas = Math.min(solverOp.gas, dConfigSolverGasLimit);

        // Deduct solver's max (C + E) gas from remainingMaxGas, for future solver gas liability calculations
        _gL.remainingMaxGas -= (_executionMaxGas + _calldataGas).toUint40();

        uint256 _gasUsed = _calldataGas + (gasWaterMark - gasleft());

        // Calculate what the solver owes
        // NOTE: This will cause an error if you are simulating with a gasPrice of 0
        if (result.bundlersFault()) {
            // CASE: Solver is not responsible for the failure of their operation, so we blame the bundler
            // and reduce the total amount refunded to the bundler
            _gasUsed += _BUNDLER_FAULT_OFFSET;
            _gL.writeoffsGas += _gasUsed.toUint40();
        } else {
            // CASE: Solver failed, so we calculate what they owe.
            _gasUsed += _SOLVER_FAULT_OFFSET;
            uint256 _gasValueWithSurcharges = _gasUsed.withSurcharge(_gL.totalSurchargeRate()) * tx.gasprice;

            EscrowAccountAccessData memory _solverAccountData = S_accessData[solverOp.from];

            // In `_assign()`, the solver's bonded AtlETH balance is reduced by `_gasValueWithSurcharges`. Any deficit
            // from that operation is returned as `_assignDeficit` below. GasLedger is not modified in _assign().
            uint256 _assignDeficit = _assign(_solverAccountData, solverOp.from, _gasValueWithSurcharges);

            // Solver's analytics updated:
            // - increment auctionFails
            // - increase totalGasValueUsed by gas cost + surcharges paid by solver, less any deficit
            _updateAnalytics(_solverAccountData, false, _gasValueWithSurcharges - _assignDeficit);

            // Persist the updated solver account data to storage
            S_accessData[solverOp.from] = _solverAccountData;

            if (_assignDeficit > 0) {
                // If any deficit, calculate the gas units unpaid for due to assign deficit.
                // Gas units written off = gas used * (deficit / gas value with surcharges) ratio.
                // `mulDivUp()` rounds in favor of writeoffs, so we don't overestimate gas that was actually paid for
                // and end up reimbursing the bundler for more than was actually taken from the solvers.
                uint256 _gasWrittenOff = _gasUsed.mulDivUp(_assignDeficit, _gasValueWithSurcharges);

                // No risk of underflow in subtraction below, because:
                // _assignDeficit is <= _gasValueWithSurcharges, so _gasWrittenOff is <= _gasUsed.

                // Deduct gas written off from gas tracked as "paid for" by failed solver
                _gasUsed -= _gasWrittenOff;
                _gL.writeoffsGas += _gasWrittenOff.toUint40(); // add to writeoffs in gasLedger
            }

            // The gas paid for here by failed solver, and gas written off due to shortfall in `_assign()`, will offset
            // what the winning solver owes in `_settle()`.
            _gL.solverFaultFailureGas += _gasUsed.toUint40();
        }

        // Persist the updated gas ledger to transient storage
        t_gasLedger = _gL.pack();
    }

    /// @notice Records the gas used during the `bidFind` phase of exPostBids as a write-off.
    /// @dev Gas used for `bidFind` is considered an overhead paid by the bundler (via reduced refund)
    ///      and is not charged to any specific solver. It's added to `writeoffsGas` in the GasLedger.
    /// @param gasUsed The amount of gas consumed during the `bidFind` phase.
    function _writeOffBidFindGas(uint256 gasUsed) internal {
        GasLedger memory _gL = t_gasLedger.toGasLedger();
        _gL.writeoffsGas += gasUsed.toUint40();
        t_gasLedger = _gL.pack();
    }

    /// @notice Charges solvers that were not reached during the metacall for the calldata gas cost of their solverOps.
    /// @dev Iterates through `solverOps` starting from the index *after* `winningSolverIdx`. For each unreached
    /// operation, `VERIFICATION.verifySolverOp` is called to determine fault.
    ///      - If bundler fault: The calldata gas is added to `gL.writeoffsGas` (reducing bundler's refund).
    ///      - If solver fault: Attempts to charge the solver's bonded `AtlETH` using `_assign` for the calldata
    ///        gas cost (no surcharges added). Any deficit is added to `gL.writeoffsGas`.
    ///      The gas cost of executing this loop is also added to `gL.writeoffsGas` to ensure the bundler pays for it.
    /// @param solverOps The SolverOperation array containing the solvers' transaction data.
    /// @param gL The GasLedger struct (memory); `gL.writeoffsGas` is updated within this function.
    /// @param winningSolverIdx Index of the winning/last attempted solver; the loop starts after this index.
    /// @param userOpHash Hash of the UserOperation, used for verification.
    /// @param maxFeePerGas userOp.maxFeePerGas, used for verification.
    /// @param bundler The metacall caller (msg.sender), used for verification.
    /// @param allowsTrustedOpHash Flag indicating with trustedOpHash is enabled in the metacall.
    /// @return unreachedCalldataValuePaid Total value successfully charged to unreached solvers (cost - deficits).
    function _chargeUnreachedSolversForCalldata(
        SolverOperation[] calldata solverOps,
        GasLedger memory gL,
        uint256 winningSolverIdx,
        bytes32 userOpHash,
        uint256 maxFeePerGas,
        address bundler,
        bool allowsTrustedOpHash
    )
        internal
        returns (uint256 unreachedCalldataValuePaid)
    {
        uint256 _writeoffGasMarker = gasleft();

        // Start at the solver after the current solverIdx, because current solverIdx is the winner
        for (uint256 i = winningSolverIdx + 1; i < solverOps.length; ++i) {
            address _from = solverOps[i].from;
            uint256 _calldataGasCost =
                GasAccLib.solverOpCalldataGas(solverOps[i].data.length, L2_GAS_CALCULATOR) * tx.gasprice;

            // Verify the solverOp, and write off solver's calldata gas if included due to bundler fault
            uint256 _result =
                VERIFICATION.verifySolverOp(solverOps[i], userOpHash, maxFeePerGas, bundler, allowsTrustedOpHash);

            if (_result.bundlersFault()) {
                gL.writeoffsGas += _calldataGasCost.divUp(tx.gasprice).toUint40();
                continue;
            }

            // If solverOp inclusion was not bundler fault, charge solver for calldata gas
            EscrowAccountAccessData memory _solverData = S_accessData[_from];

            // No surcharges added to calldata cost for unreached solvers
            uint256 _deficit = _assign(_solverData, _from, _calldataGasCost);

            // Persist _assign() changes to solver account data to storage
            S_accessData[_from] = _solverData;

            // The sum of value paid less deficits is tracked and used in `_settle()`
            unreachedCalldataValuePaid += _calldataGasCost - _deficit;

            // Any deficits from the `_assign()` operations are converted to gas units and written off so as not to
            // charge the winning solver for calldata that is not their responsibility, in `_settle()`.
            if (_deficit > 0) gL.writeoffsGas += _deficit.divUp(tx.gasprice).toUint40();
        }

        // The gas cost of this loop is always paid by the bundler so as not to charge the winning solver for an
        // excessive number of loops and SSTOREs via `_assign()`. This gas is therefore added to writeoffs.
        gL.writeoffsGas += (_writeoffGasMarker - gasleft()).toUint40();
    }

    /// @notice Finalizes gas accounting at the end of the metacall, settles balances, and pays refunds/surcharges.
    /// @param ctx The context struct (memory), used for ctx.bundler and ctx.solverSuccessful.
    /// @param gL The final state of the GasLedger struct (memory), used for gas calculations.
    /// @param gasMarker The initial gas measurement taken at the start of the metacall.
    /// @param gasRefundBeneficiary The address designated to receive the bundler's gas refund. Defaults to
    /// `ctx.bundler`.
    /// @param unreachedCalldataValuePaid The total value successfully collected from unreached solvers for their
    /// calldata costs (from `_chargeUnreachedSolversForCalldata`).
    /// @param multipleSuccessfulSolvers A boolean indicating whether the multipleSuccessfulSolvers mode is enabled.
    /// @return claimsPaidToBundler The net amount of ETH transferred to the `gasRefundBeneficiary`.
    /// @return netAtlasGasSurcharge The net amount of ETH taken as Atlas surcharge during the metacall.
    function _settle(
        Context memory ctx,
        GasLedger memory gL,
        uint256 gasMarker,
        address gasRefundBeneficiary,
        uint256 unreachedCalldataValuePaid,
        bool multipleSuccessfulSolvers
    )
        internal
        returns (uint256 claimsPaidToBundler, uint256 netAtlasGasSurcharge)
    {
        EscrowAccountAccessData memory _winningSolverData;
        BorrowsLedger memory _bL = t_borrowsLedger.toBorrowsLedger();
        (address _winningSolver,,) = _solverLockData();

        // No need to SLOAD bonded balance etc. if no winning solver
        if (ctx.solverSuccessful) _winningSolverData = S_accessData[_winningSolver];

        // Send gas refunds to bundler if no gas refund beneficiary specified
        if (gasRefundBeneficiary == address(0)) gasRefundBeneficiary = ctx.bundler;

        // First check if all borrows have been repaid.
        // Borrows can only be repaid in native token, not bonded AtlETH.
        // This is also done at end of solverCall(), so check here only needed for zero solvers case.
        int256 _netRepayments = _bL.netRepayments();
        if (_netRepayments < 0) revert BorrowsNotRepaid(_bL.borrows, _bL.repays);

        uint256 _winnerGasCharge;
        uint256 _gasLeft = gasleft();

        // NOTE: Trivial for bundler to run a different EOA for solver so no bundler == solver carveout.
        if (ctx.solverSuccessful) {
            // CASE: Winning solver.

            // Winning solver should pay for:
            // - Gas (C + E) used by their solverOp
            // - Gas (C + E) used by userOp, dapp hooks, and other metacall overhead
            // Winning solver should not pay for:
            // - Gas (C + E) used by other reached solvers (bundler or solver fault failures)
            // - Gas (C only) used by unreached solvers
            // - Gas (E only) used during the bid-finding or unreached solver calldata charge loops
            _winnerGasCharge = gasMarker - gL.writeoffsGas - gL.solverFaultFailureGas
                - (unreachedCalldataValuePaid / tx.gasprice) - _gasLeft;
            uint256 _surchargedGasPaidBySolvers = gL.solverFaultFailureGas + _winnerGasCharge;

            // Bundler gets base gas cost + bundler surcharge of (solver fault fails + winning solver charge)
            // Bundler also gets reimbursed for the calldata of unreached solvers (only base, no surcharge)
            claimsPaidToBundler = (_surchargedGasPaidBySolvers.withSurcharge(gL.bundlerSurchargeRate) * tx.gasprice)
                + unreachedCalldataValuePaid;

            // Atlas gets only the Atlas surcharge of (solver fault fails + winning solver charge)
            netAtlasGasSurcharge = _surchargedGasPaidBySolvers.getSurcharge(gL.atlasSurchargeRate) * tx.gasprice;

            // Calculate what winning solver pays: add surcharges and multiply by gas price
            _winnerGasCharge = _winnerGasCharge.withSurcharge(gL.totalSurchargeRate()) * tx.gasprice;

            uint256 _deficit; // Any shortfall that the winning solver is not able to repay from bonded balance
            if (_winnerGasCharge < uint256(_netRepayments)) {
                // CASE: solver recieves more than they pay --> net credit to account
                _credit(_winningSolverData, uint256(_netRepayments) - _winnerGasCharge);
            } else {
                // CASE: solver pays more than they recieve --> net assign to account
                _deficit = _assign(_winningSolverData, _winningSolver, _winnerGasCharge - uint256(_netRepayments));
            }

            if (_deficit > claimsPaidToBundler) revert AssignDeficitTooLarge(_deficit, claimsPaidToBundler);
            claimsPaidToBundler -= _deficit;

            _updateAnalytics(_winningSolverData, true, _winnerGasCharge);

            // Persist the updated winning solver account data to storage
            S_accessData[_winningSolver] = _winningSolverData;
        } else {
            // CASE: No winning solver.

            // Bundler may still recover a partial refund (from solver fault failure charges) up to 80% of the gas cost
            // of the metacall. The remaining 20% could be recovered through storage refunds, and it is important that
            // metacalls with no winning solver are not profitable for the bundler.
            // The exception to this rule is when multipleSuccessfulSolvers is set to true. In this case, all solvers
            // should be able to execute and pay for their own gas + surcharges, but the bundler refund should not be
            // capped.

            uint256 _maxRefund;
            if (multipleSuccessfulSolvers) {
                _maxRefund = type(uint256).max;
            } else {
                _maxRefund = (gasMarker - gL.writeoffsGas - _gasLeft).maxBundlerRefund() * tx.gasprice;
            }

            // Bundler gets (base gas cost + bundler surcharge) of solver fault failures, plus base gas cost of
            // unreached solver calldata. This is compared to _maxRefund below. Net repayments is added after the 80%
            // cap has been applied to the gas refund components.
            // `unreachedCalldataValuePaid` is not added here as it should always be 0 when solverSuccessful = false,
            // because there should then be no unreached solvers.
            uint256 _bundlerCutBeforeLimit =
                uint256(gL.solverFaultFailureGas).withSurcharge(gL.bundlerSurchargeRate) * tx.gasprice;

            // Atlas only keeps the Atlas surcharge of solver fault failures, and any gas due to bundler that exceeds
            // the 80% limit.
            netAtlasGasSurcharge = uint256(gL.solverFaultFailureGas).getSurcharge(gL.atlasSurchargeRate) * tx.gasprice;

            if (_bundlerCutBeforeLimit > _maxRefund) {
                // More than max gas refund was taken by failed/unreached solvers, excess goes to Atlas
                claimsPaidToBundler = _maxRefund;
                netAtlasGasSurcharge += _bundlerCutBeforeLimit - _maxRefund;
            } else {
                // Otherwise, the bundler can receive the full solver fault failure gas
                claimsPaidToBundler = _bundlerCutBeforeLimit;
            }

            // Finally, add any net repayments, which should not be subject to the 80% cap, to the bundler's claims
            claimsPaidToBundler += uint256(_netRepayments);
        }

        S_cumulativeSurcharge += netAtlasGasSurcharge;

        // Set lock to FullyLocked to prevent any reentrancy possibility in refund transfer below
        _setLockPhase(uint8(ExecutionPhase.FullyLocked));

        if (claimsPaidToBundler != 0) SafeTransferLib.safeTransferETH(gasRefundBeneficiary, claimsPaidToBundler);
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

    /// @notice Checks all obligations have been reconciled: native borrows AND gas liabilities.
    /// @return True if both dimensions are reconciled, false otherwise.
    function _isBalanceReconciled(bool multipleSuccessfulSolvers) internal view returns (bool) {
        GasLedger memory gL = t_gasLedger.toGasLedger();
        BorrowsLedger memory bL = t_borrowsLedger.toBorrowsLedger();

        // DApp's excess repayments via `contribute()` can offset solverGasLiability.
        // NOTE: This solver gas subsidy feature is disabled in multipleSuccessfulSolvers mode.
        uint256 _netRepayments;
        if (!multipleSuccessfulSolvers && bL.repays > bL.borrows) _netRepayments = bL.repays - bL.borrows;

        // gL.maxApprovedGasSpend only stores the gas units, must be scaled by tx.gasprice
        uint256 _maxApprovedGasValue = gL.maxApprovedGasSpend * tx.gasprice;

        return (bL.repays >= bL.borrows) && (_maxApprovedGasValue + _netRepayments >= gL.solverGasLiability());
    }
}
