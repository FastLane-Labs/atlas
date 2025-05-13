//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { AtlETH } from "./AtlETH.sol";
import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";
import { IAtlas } from "../interfaces/IAtlas.sol";
import { ISolverContract } from "../interfaces/ISolverContract.sol";
import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";

import { SafeCall } from "../libraries/SafeCall/SafeCall.sol";
import { EscrowBits } from "../libraries/EscrowBits.sol";
import { CallBits } from "../libraries/CallBits.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol";
import { AccountingMath } from "../libraries/AccountingMath.sol";
import { GasAccLib, GasLedger } from "../libraries/GasAccLib.sol";
import { DAppConfig } from "../types/ConfigTypes.sol";
import "../types/SolverOperation.sol";
import "../types/UserOperation.sol";
import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

/// @title Escrow
/// @author FastLane Labs
/// @notice This Escrow component of Atlas handles execution of stages by calling corresponding functions on the
/// Execution Environment contract.
abstract contract Escrow is AtlETH {
    using EscrowBits for uint256;
    using CallBits for uint32;
    using SafetyBits for Context;
    using SafeCall for address;
    using SafeCast for uint256;
    using AccountingMath for uint256;
    using GasAccLib for uint256;
    using GasAccLib for GasLedger;

    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator
    )
        AtlETH(escrowDuration, atlasSurchargeRate, verification, simulator, initialSurchargeRecipient, l2GasCalculator)
    {
        if (escrowDuration == 0) revert InvalidEscrowDuration();
    }

    /// @notice Executes the preOps logic defined in the Execution Environment.
    /// @param ctx Metacall context data from the Context struct.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @return preOpsData The data returned by the preOps call, if successful.
    function _executePreOpsCall(
        Context memory ctx,
        DAppConfig memory dConfig,
        UserOperation calldata userOp
    )
        internal
        withLockPhase(ExecutionPhase.PreOps)
        returns (bytes memory)
    {
        uint256 _dappGasWaterMark = gasleft();

        (bool _success, bytes memory _data) = ctx.executionEnvironment.call{ gas: ctx.dappGasLeft }(
            abi.encodePacked(
                abi.encodeCall(IExecutionEnvironment.preOpsWrapper, userOp), ctx.setAndPack(ExecutionPhase.PreOps)
            )
        );

        _updateDAppGasLeft(ctx, _dappGasWaterMark);

        if (_success) {
            if (dConfig.callConfig.needsPreOpsReturnData()) {
                return abi.decode(_data, (bytes));
            } else {
                return new bytes(0);
            }
        }

        if (ctx.isSimulation) revert PreOpsSimFail();
        revert PreOpsFail();
    }

    /// @notice Executes the user operation logic defined in the Execution Environment.
    /// @param ctx Metacall context data from the Context struct.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct containing the user's transaction data.
    /// @param returnData Data returned from previous call phases.
    /// @return userData Data returned from executing the UserOperation, if the call was successful.
    function _executeUserOperation(
        Context memory ctx,
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        bytes memory returnData
    )
        internal
        withLockPhase(ExecutionPhase.UserOperation)
        returns (bytes memory)
    {
        bool _success;
        bytes memory _data;

        if (!_borrow(userOp.value)) {
            revert InsufficientEscrow();
        }

        (_success, _data) = ctx.executionEnvironment.call{ value: userOp.value, gas: userOp.gas }(
            abi.encodePacked(
                abi.encodeCall(IExecutionEnvironment.userWrapper, userOp), ctx.setAndPack(ExecutionPhase.UserOperation)
            )
        );

        if (_success) {
            // Handle formatting of returnData
            if (dConfig.callConfig.needsUserReturnData()) {
                return abi.decode(_data, (bytes));
            } else {
                return returnData;
            }
        }

        // revert for failed
        if (ctx.isSimulation) revert UserOpSimFail();
        revert UserOpFail();
    }

    /// @notice Checks if the trusted operation hash matches and sets the appropriate error bit if it doesn't.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param prevalidated Boolean flag indicating whether the SolverOperation has been prevalidated to skip certain
    /// checks.
    /// @param userOp UserOperation struct containing the user's transaction data relevant to this SolverOperation.
    /// @param solverOp SolverOperation struct containing the solver's bid and execution data.
    /// @param result The current result bitmask that tracks the status of various checks and validations.
    /// @return The updated result bitmask with the AltOpHashMismatch bit set if the operation hash does not match.
    function _checkTrustedOpHash(
        DAppConfig memory dConfig,
        bool prevalidated,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        uint256 result
    )
        internal
        returns (uint256)
    {
        if (dConfig.callConfig.allowsTrustedOpHash() && !prevalidated && !_handleAltOpHash(userOp, solverOp)) {
            result |= 1 << uint256(SolverOutcome.AltOpHashMismatch);
        }
        return result;
    }

    /// @notice Attempts to execute a SolverOperation and determine if it wins the auction.
    /// @param ctx Context struct containing the current state of the escrow lock.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct containing the user's transaction data relevant to this SolverOperation.
    /// @param solverOp SolverOperation struct containing the solver's bid and execution data.
    /// @param bidAmount The amount of bid submitted by the solver for this operation.
    /// @param gasWaterMark The gas left at the start of the current solverOp's execution, to be used to charge/write
    /// off solverOp gas.
    /// @param prevalidated Boolean flag indicating if the solverOp has been prevalidated in bidFind (exPostBids).
    /// @param returnData Data returned from UserOp execution, used as input if necessary.
    /// @return bidAmount The determined bid amount for the SolverOperation if all validations pass and the operation is
    /// executed successfully; otherwise, returns 0.
    function _executeSolverOperation(
        Context memory ctx,
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        uint256 bidAmount,
        uint256 gasWaterMark,
        bool prevalidated,
        bytes memory returnData
    )
        internal
        returns (uint256)
    {
        GasLedger memory _gL = t_gasLedger.toGasLedger();
        uint256 _result;

        // Decrease unreachedSolverGas and reset maxApprovedGasSpend at the start of each solverOp
        _adjustGasLedgerAtSolverOpStart(_gL, dConfig, solverOp);
        t_gasLedger = _gL.pack(); // Persist changes to transient storage

        if (!prevalidated) {
            _result = VERIFICATION.verifySolverOp(
                solverOp, ctx.userOpHash, userOp.maxFeePerGas, ctx.bundler, dConfig.callConfig.allowsTrustedOpHash()
            );
            _result = _checkSolverBidToken(solverOp.bidToken, dConfig.bidToken, _result);
        }

        // Verify the transaction.
        if (_result.canExecute()) {
            uint256 _gasLimit;
            // Verify gasLimit again
            (_result, _gasLimit) = _validateSolverOpGasAndValue(_gL, dConfig, solverOp, gasWaterMark, _result);
            _result |= _validateSolverOpDeadline(solverOp, dConfig);

            // Check for trusted operation hash
            _result = _checkTrustedOpHash(dConfig, prevalidated, userOp, solverOp, _result);

            // If there are no errors, attempt to execute
            if (_result.canExecute()) {
                SolverTracker memory _solverTracker;

                // Execute the solver call
                (_result, _solverTracker) = _solverOpWrapper(ctx, solverOp, bidAmount, _gasLimit, returnData);

                // First successful solver call that paid what it bid
                if (_result.executionSuccessful()) {
                    // Logic done above `_handleSolverFailAccounting()` is to charge solver for gas used here
                    ctx.solverOutcome = uint24(_result);

                    emit SolverTxResult(
                        solverOp.solver,
                        solverOp.from,
                        dConfig.to,
                        solverOp.bidToken,
                        _solverTracker.bidAmount,
                        true,
                        true,
                        _result
                    );

                    // Keep executing solvers without ending the auction if multipleSuccessfulSolvers is set
                    if (dConfig.callConfig.multipleSuccessfulSolvers()) {
                        // multipleSuccessfulSolvers mode:
                        // - `ctx.solverSuccessful` is implicitly left as false
                        // - `_result` should be 0 (successful) below, which should charge the solver for their own
                        //   gas + surcharges, as 0 is not captured in the bundler fault block.
                        // - exPostBids is not supported in multipleSuccessfulSolvers mode, so exPostBids = false here.
                        _handleSolverFailAccounting(solverOp, dConfig.solverGasLimit, gasWaterMark, _result, false);
                    } else {
                        // If not in multipleSuccessfulSolvers mode, end the auction with the first successful solver
                        // that paid what it bid.
                        // We intentionally do not change GasLedger here as we have found a winning solver and don't
                        // need it anymore
                        ctx.solverSuccessful = true;
                    }

                    return _solverTracker.bidAmount;
                }
            }
        }

        // If we reach this point, the solver call did not execute successfully.
        ctx.solverOutcome = uint24(_result);

        emit SolverTxResult(
            solverOp.solver,
            solverOp.from,
            dConfig.to,
            solverOp.bidToken,
            bidAmount,
            _result.executedWithError(),
            false,
            _result
        );

        // Account for failed SolverOperation gas costs
        _handleSolverFailAccounting(
            solverOp, dConfig.solverGasLimit, gasWaterMark, _result, dConfig.callConfig.exPostBids()
        );

        return 0;
    }

    /// @notice Allocates the winning bid amount after a successful SolverOperation execution.
    /// @dev This function handles the allocation of the bid amount to the appropriate recipients as defined in the
    /// DApp's configuration. It calls the allocateValue function in the Execution Environment, which is responsible for
    /// distributing the bid amount. Note that balance discrepancies leading to payment failures are typically due to
    /// issues in the DAppControl contract, not the execution environment itself.
    /// @param ctx Context struct containing the current state of the escrow lock.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param bidAmount The winning solver's bid amount, to be allocated.
    /// @param returnData Data returned from the execution of the UserOperation, which may influence how the bid amount
    /// is allocated.
    function _allocateValue(
        Context memory ctx,
        DAppConfig memory dConfig,
        uint256 bidAmount,
        bytes memory returnData
    )
        internal
        withLockPhase(ExecutionPhase.AllocateValue)
    {
        uint256 _dappGasWaterMark = gasleft();

        (bool _success,) = ctx.executionEnvironment.call{ gas: ctx.dappGasLeft }(
            abi.encodePacked(
                abi.encodeCall(
                    IExecutionEnvironment.allocateValue, (ctx.solverSuccessful, dConfig.bidToken, bidAmount, returnData)
                ),
                ctx.setAndPack(ExecutionPhase.AllocateValue)
            )
        );

        _updateDAppGasLeft(ctx, _dappGasWaterMark);

        // Revert if allocateValue failed at any point.
        if (!_success) {
            if (ctx.isSimulation) revert AllocateValueSimFail();
            revert AllocateValueFail();
        }
    }

    /// @notice Adjusts the gas ledger before evaluating a SolverOperation.
    /// @dev Updates the in-memory `gL` by decreasing `unreachedSolverGas` based on the current solverOp's max potential
    /// gas (execution + calldata if not exPostBids) and resets `maxApprovedGasSpend` to 0. Caller must persist `gL`
    /// changes to transient storage separately.
    /// @param gL The GasLedger struct (in memory) to modify.
    /// @param dConfig DApp configuration containing `solverGasLimit` and `callConfig`.
    /// @param solverOp The SolverOperation being evaluated.
    function _adjustGasLedgerAtSolverOpStart(
        GasLedger memory gL,
        DAppConfig memory dConfig,
        SolverOperation calldata solverOp
    )
        internal
        view
    {
        // Decrease unreachedSolverGas by the current solverOp's (C + E) max gas
        uint256 _calldataGas;

        // Solver's execution gas is solverOp.gas with a ceiling of dConfig.solverGasLimit
        uint256 _executionGas = Math.min(solverOp.gas, dConfig.solverGasLimit);

        // Calldata gas is only included if NOT in exPostBids mode.
        if (!dConfig.callConfig.exPostBids()) {
            _calldataGas = GasAccLib.solverOpCalldataGas(solverOp.data.length, L2_GAS_CALCULATOR);
        }

        // Reset solver's max approved gas spend to 0 at start of each new solver execution
        gL.maxApprovedGasSpend = 0;
        gL.unreachedSolverGas -= (_executionGas + _calldataGas).toUint40();

        // NOTE: GasLedger changes must be persisted to transient storage separately after this function call
    }

    /// @notice Validates a SolverOperation's gas requirements against the escrow state.
    /// @dev Performs a series of checks to ensure that a SolverOperation can be executed within the defined parameters
    /// and limits. This includes verifying that the operation is within the gas limit and that the solver has
    /// sufficient balance in escrow to cover the gas costs.
    /// @param gL The GasLedger memory struct containing the current gas accounting state.
    /// @param dConfig DApp configuration data, including solver gas limits and operation parameters.
    /// @param solverOp The SolverOperation being validated.
    /// @param gasWaterMark The initial gas measurement before validation begins, used to ensure enough gas remains for
    /// validation logic.
    /// @param result The current result bitmap, which will be updated with the outcome of the gas validation checks.
    /// @return result Updated result flags after performing the validation checks, including any new errors
    /// encountered.
    /// @return gasLimit The calculated gas limit for the SolverOperation, considering the operation's gas usage and
    /// the protocol's gas buffers.
    function _validateSolverOpGasAndValue(
        GasLedger memory gL,
        DAppConfig memory dConfig,
        SolverOperation calldata solverOp,
        uint256 gasWaterMark,
        uint256 result
    )
        internal
        view
        returns (uint256, uint256 gasLimit)
    {
        // gasLimit is solverOp.gas, with a ceiling of dConfig.solverGasLimit
        gasLimit = Math.min(solverOp.gas, dConfig.solverGasLimit);

        if (gasWaterMark < _VALIDATION_GAS_LIMIT + gasLimit) {
            // Make sure to leave enough gas for dApp validation calls
            result |= 1 << uint256(SolverOutcome.UserOutOfGas);
            return (result, gasLimit);
        }

        // Verify that we can lend the solver their tx value
        if (solverOp.value > address(this).balance) {
            result |= 1 << uint256(SolverOutcome.CallValueTooHigh);
            return (result, gasLimit);
        }

        uint256 _solverBalance = S_accessData[solverOp.from].bonded;

        // Checks if solver's bonded balance is enough to cover the max charge should they win, including surcharges
        if (_solverBalance < gL.solverGasLiability()) {
            result |= 1 << uint256(SolverOutcome.InsufficientEscrow);
        }

        return (result, gasLimit);
    }

    /// @notice Validates a SolverOperation's deadline against the current block.
    /// @param solverOp The SolverOperation being validated.
    /// @param dConfig DApp configuration data, including solver gas limits and operation parameters.
    /// @return result Updated result flags after performing the validation checks, including any new errors
    function _validateSolverOpDeadline(
        SolverOperation calldata solverOp,
        DAppConfig memory dConfig
    )
        internal
        view
        returns (uint256 result)
    {
        if (solverOp.deadline != 0 && block.number > solverOp.deadline) {
            result |= (
                1
                    << uint256(
                        dConfig.callConfig.allowsTrustedOpHash()
                            ? uint256(SolverOutcome.DeadlinePassedAlt)
                            : uint256(SolverOutcome.DeadlinePassed)
                    )
            );
            return result;
        }

        uint256 lastAccessedBlock = S_accessData[solverOp.from].lastAccessedBlock;

        if (lastAccessedBlock >= block.number) {
            result |= 1 << uint256(SolverOutcome.PerBlockLimit);
        }
    }

    /// @notice Determines the bid amount for a SolverOperation based on verification and validation results.
    /// @dev This function assesses whether a SolverOperation meets the criteria for execution by verifying it against
    /// the Atlas protocol's rules and the current Context lock state. It checks for valid execution based on the
    /// SolverOperation's specifics, like gas usage and deadlines. The function aims to protect against malicious
    /// bundlers by ensuring solvers are not unfairly charged for on-chain bid finding gas usage. If the operation
    /// passes verification and validation, and if it's eligible for bid amount determination, the function
    /// attempts to execute and determine the bid amount.
    /// @param ctx The Context struct containing the current state of the escrow lock.
    /// @param dConfig The DApp configuration data, including parameters relevant to solver bid validation.
    /// @param userOp The UserOperation associated with this SolverOperation, providing context for the bid amount
    /// determination.
    /// @param solverOp The SolverOperation being assessed, containing the solver's bid amount.
    /// @param returnData Data returned from the execution of the UserOp call.
    /// @return bidAmount The determined bid amount for the SolverOperation if all validations pass and the operation is
    /// executed successfully; otherwise, returns 0.
    function _getBidAmount(
        Context memory ctx,
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        bytes memory returnData
    )
        internal
        returns (uint256 bidAmount)
    {
        // NOTE: To prevent a malicious bundler from aggressively collecting storage refunds,
        // solvers should not be on the hook for any 'onchain bid finding' gas usage.

        uint256 _gasWaterMark = gasleft();
        uint256 _gasLimit;
        GasLedger memory _gL = t_gasLedger.toGasLedger();

        // Decrease unreachedSolverGas and reset maxApprovedGasSpend at the start of each solverOp
        _adjustGasLedgerAtSolverOpStart(_gL, dConfig, solverOp);
        t_gasLedger = _gL.pack(); // Persist changes to transient storage

        uint256 _result = VERIFICATION.verifySolverOp(
            solverOp, ctx.userOpHash, userOp.maxFeePerGas, ctx.bundler, dConfig.callConfig.allowsTrustedOpHash()
        );

        _result = _checkSolverBidToken(solverOp.bidToken, dConfig.bidToken, _result);
        (_result, _gasLimit) = _validateSolverOpGasAndValue(_gL, dConfig, solverOp, _gasWaterMark, _result);
        _result |= _validateSolverOpDeadline(solverOp, dConfig);

        // Verify the transaction.
        if (!_result.canExecute()) return 0;

        if (dConfig.callConfig.allowsTrustedOpHash()) {
            if (!_handleAltOpHash(userOp, solverOp)) {
                return (0);
            }
        }

        (bool _success, bytes memory _data) = address(this).call{ gas: _gasLimit }(
            abi.encodeCall(this.solverCall, (ctx, solverOp, solverOp.bidAmount, returnData))
        );

        // The `solverCall()` above should always revert as key.bidFind is always true when it's called in the context
        // of this function. Therefore `success` should always be false below, and the revert should be unreachable.
        if (_success) {
            revert Unreachable();
        }

        if (bytes4(_data) == BidFindSuccessful.selector) {
            // Get the uint256 from the memory array
            assembly {
                let dataLocation := add(_data, 0x20)
                bidAmount := mload(add(dataLocation, sub(mload(_data), 32)))
            }
            return bidAmount;
        }

        return 0;
    }

    /// @notice Validates UserOp hashes provided by the SolverOperation, using the alternative set of hashed parameters.
    /// @param userOp The UserOperation struct, providing the baseline parameters for comparison.
    /// @param solverOp The SolverOperation struct being validated against the UserOperation.
    /// @return A boolean value indicating whether the SolverOperation passed the alternative hash check, with `true`
    /// meaning it is considered valid
    function _handleAltOpHash(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        internal
        returns (bool)
    {
        // These failures should be attributed to bundler maliciousness
        if (userOp.control != solverOp.control) {
            return false;
        }
        if (!(userOp.deadline == 0 || solverOp.deadline == 0 || solverOp.deadline == userOp.deadline)) {
            return false;
        }
        bytes32 _hashId = keccak256(abi.encodePacked(solverOp.userOpHash, solverOp.from, solverOp.deadline));
        if (S_solverOpHashes[_hashId]) {
            return false;
        }
        S_solverOpHashes[_hashId] = true;
        return true;
    }

    /// @notice Checks if the solver's bid token matches the dApp's bid token.
    /// @param solverBidToken The solver's bid token address.
    /// @param dConfigBidToken The dApp's bid token address.
    /// @param result The current result bitmap, which will be updated with the outcome of the bid token check.
    /// @return The updated result bitmap, with the SolverOutcome.InvalidBidToken flag set if the bid token check fails.
    function _checkSolverBidToken(
        address solverBidToken,
        address dConfigBidToken,
        uint256 result
    )
        internal
        pure
        returns (uint256)
    {
        if (solverBidToken != dConfigBidToken) {
            return result | 1 << uint256(SolverOutcome.InvalidBidToken);
        }
        return result;
    }

    /// @notice Wraps the execution of a SolverOperation and handles potential errors.
    /// @param ctx The current lock data.
    /// @param solverOp The SolverOperation struct containing the operation's execution data.
    /// @param bidAmount The bid amount associated with the SolverOperation.
    /// @param gasLimit The gas limit for executing the SolverOperation, calculated based on the operation's
    /// requirements and protocol buffers.
    /// @param returnData Data returned from the execution of the associated UserOperation, which may be required
    /// for the SolverOperation's logic.
    /// @return result SolverOutcome enum value encoded as a uint256 bitmap, representing the result of the
    /// SolverOperation
    /// @return solverTracker Tracking data for the solver's bid
    function _solverOpWrapper(
        Context memory ctx,
        SolverOperation calldata solverOp,
        uint256 bidAmount,
        uint256 gasLimit,
        bytes memory returnData
    )
        internal
        returns (uint256 result, SolverTracker memory solverTracker)
    {
        // Calls the solverCall function, just below this function, which will handle calling solverPreTryCatch and
        // solverPostTryCatch via the ExecutionEnvironment, and in between those two hooks, the actual solver call
        // directly from Atlas to the solver contract (not via the ExecutionEnvironment).
        (bool _success, bytes memory _data) =
            address(this).call{ gas: gasLimit }(abi.encodeCall(this.solverCall, (ctx, solverOp, bidAmount, returnData)));

        if (_success) {
            // If solverCall() was successful, intentionally leave uint256 result unset as 0 indicates success.
            solverTracker = abi.decode(_data, (SolverTracker));
        } else {
            // If solverCall() failed, catch the error and encode the failure case in the result uint accordingly.
            bytes4 _errorSwitch = bytes4(_data);
            if (_errorSwitch == AlteredControl.selector) {
                result = 1 << uint256(SolverOutcome.AlteredControl);
            } else if (_errorSwitch == InsufficientEscrow.selector) {
                result = 1 << uint256(SolverOutcome.InsufficientEscrow);
            } else if (_errorSwitch == PreSolverFailed.selector) {
                result = 1 << uint256(SolverOutcome.PreSolverFailed);
            } else if (_errorSwitch == SolverOpReverted.selector) {
                result = 1 << uint256(SolverOutcome.SolverOpReverted);
            } else if (_errorSwitch == PostSolverFailed.selector) {
                result = 1 << uint256(SolverOutcome.PostSolverFailed);
            } else if (_errorSwitch == BidNotPaid.selector) {
                result = 1 << uint256(SolverOutcome.BidNotPaid);
            } else if (_errorSwitch == InvalidSolver.selector) {
                result = 1 << uint256(SolverOutcome.InvalidSolver);
            } else if (_errorSwitch == BalanceNotReconciled.selector) {
                result = 1 << uint256(SolverOutcome.BalanceNotReconciled);
            } else if (_errorSwitch == CallbackNotCalled.selector) {
                result = 1 << uint256(SolverOutcome.CallbackNotCalled);
            } else if (_errorSwitch == InvalidEntry.selector) {
                // DAppControl is attacking solver contract - treat as AlteredControl
                result = 1 << uint256(SolverOutcome.AlteredControl);
            } else {
                result = 1 << uint256(SolverOutcome.EVMError);
            }
        }
    }

    /// @notice Executes the SolverOperation logic, including preSolver and postSolver hooks via the Execution
    /// Environment, as well as the actual solver call directly from Atlas to the solver contract.
    /// @param ctx The Context struct containing lock data and the Execution Environment address.
    /// @param solverOp The SolverOperation to be executed.
    /// @param bidAmount The bid amount associated with the SolverOperation.
    /// @param returnData Data returned from previous call phases.
    /// @return solverTracker Additional data for handling the solver's bid in different scenarios.
    function solverCall(
        Context memory ctx,
        SolverOperation calldata solverOp,
        uint256 bidAmount,
        bytes calldata returnData
    )
        external
        payable
        returns (SolverTracker memory solverTracker)
    {
        if (msg.sender != address(this)) revert InvalidEntry();

        bytes memory _data;
        bool _success;

        // Set the solver lock and solver address at the beginning to ensure reliability
        t_solverLock = uint256(uint160(solverOp.from));
        t_solverTo = solverOp.solver;

        // ------------------------------------- //
        //             Pre-Solver Call           //
        // ------------------------------------- //

        _setLockPhase(uint8(ExecutionPhase.PreSolver));

        (_success, _data) = ctx.executionEnvironment.call(
            abi.encodePacked(
                abi.encodeCall(IExecutionEnvironment.solverPreTryCatch, (bidAmount, solverOp, returnData)),
                ctx.setAndPack(ExecutionPhase.PreSolver)
            )
        );

        // If ExecutionEnvironment.solverPreTryCatch() failed, bubble up the error
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        // Update solverTracker with returned data
        solverTracker = abi.decode(_data, (SolverTracker));

        // ------------------------------------- //
        //              Solver Call              //
        // ------------------------------------- //

        _setLockPhase(uint8(ExecutionPhase.SolverOperation));

        // Make sure there's enough value in Atlas for the Solver
        if (!_borrow(solverOp.value)) revert InsufficientEscrow();

        // Load callConfig from transient storage once here, to be used below.
        uint32 _callConfig = _activeCallConfig();

        // NOTE: The solver's bidAmount is always sent to their solver contract during the solver call. In exPostBids
        // mode, it is possible for a solver to encode some infomation calculated during the bid-finding process, which
        // the bundler pays for as that gas cost is written off, in the least significant bits of their bidAmount. This
        // information can be used to minimize the gas cost a solver is charged for during real execution. This is seen
        // as a feature, because the decrease in gas cost paid by the solver should result in a higher bid they are able
        // to make - a better outcome for the bid recipient.

        // Optimism's SafeCall lib allows us to limit how much returndata gets copied to memory, to prevent OOG attacks.
        _success = solverOp.solver.safeCall(
            gasleft(),
            solverOp.value,
            abi.encodeCall(
                ISolverContract.atlasSolverCall,
                (
                    solverOp.from,
                    ctx.executionEnvironment,
                    solverOp.bidToken,
                    bidAmount,
                    solverOp.data,
                    // Only pass the returnData (either from userOp or preOps) if the dApp requires it
                    _callConfig.forwardReturnData() ? returnData : new bytes(0)
                )
            )
        );

        if (!_success) revert SolverOpReverted();

        // ------------------------------------- //
        //            Post-Solver Call           //
        // ------------------------------------- //

        _setLockPhase(uint8(ExecutionPhase.PostSolver));

        (_success, _data) = ctx.executionEnvironment.call(
            abi.encodePacked(
                abi.encodeCall(IExecutionEnvironment.solverPostTryCatch, (solverOp, returnData, solverTracker)),
                ctx.setAndPack(ExecutionPhase.PostSolver)
            )
        );

        // If ExecutionEnvironment.solverPostTryCatch() failed, bubble up the error
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        // Update solverTracker with returned data
        solverTracker = abi.decode(_data, (SolverTracker));

        // ------------------------------------- //
        //              Final Checks             //
        // ------------------------------------- //

        // Verify that the solver repaid their borrowed solverOp.value by calling `reconcile()`. If `reconcile()` did
        // not fully repay the borrowed amount, the `postSolverCall` might have covered the outstanding debt via
        // `contribute()`. This final check ensures that the solver has fulfilled their repayment obligations before
        // proceeding.
        bool _multiSuccesfulSolvers = _callConfig.multipleSuccessfulSolvers();
        (, bool _calledback, bool _fulfilled) = _solverLockData();
        if (!_calledback) revert CallbackNotCalled();
        if (!_fulfilled && !_isBalanceReconciled(_multiSuccesfulSolvers)) revert BalanceNotReconciled();

        // Check if this is an on-chain, ex post bid search by verifying the `ctx.bidFind` flag.
        // If the flag is set, revert with `BidFindSuccessful` and include the solver's bid amount in `solverTracker`.
        // This indicates that the bid search process has completed successfully.
        if (ctx.bidFind) revert BidFindSuccessful(solverTracker.bidAmount);
    }

    /// Updates ctx.dappGasLeft based on the gas used in the DApp hook call just performed.
    /// @dev Measure the gasWaterMarkBefore using `gasleft()` just before performing the DApp hook call.
    /// @dev Will revert if the gas used exceeds the remaining dappGasLeft.
    /// @param ctx Memory pointer to the metacalls' Context object.
    /// @param gasWaterMarkBefore The gasleft() value just before the DApp hook call.
    function _updateDAppGasLeft(Context memory ctx, uint256 gasWaterMarkBefore) internal view {
        uint256 _gasUsed = gasWaterMarkBefore - gasleft();

        if (_gasUsed > ctx.dappGasLeft) revert DAppGasLimitReached();

        // No need to SafeCast - will revert above if too large for uint32
        ctx.dappGasLeft -= uint32(_gasUsed);
    }

    receive() external payable { }
}
