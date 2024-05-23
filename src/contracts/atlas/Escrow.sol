//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { AtlETH } from "./AtlETH.sol";

import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";

import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";
import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";

/// @title Escrow
/// @author FastLane Labs
/// @notice This Escrow component of Atlas handles execution of stages by calling corresponding functions on the
/// Execution Environment contract.
abstract contract Escrow is AtlETH {
    using EscrowBits for uint256;
    using CallBits for uint32;
    using SafetyBits for EscrowKey;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        AtlETH(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    /// @notice Executes the preOps logic defined in the Execution Environment.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @param environment Address of the execution environment contract of the current metacall tx.
    /// @param lockBytes Packed bytes form of the current escrow lock state, encoded from the EscrowKey struct.
    /// @return success Boolean indicating the success of the preOps call.
    /// @return preOpsData The data returned by the preOps call, if successful.
    function _executePreOpsCall(
        UserOperation calldata userOp,
        address environment,
        bytes memory lockBytes
    )
        internal
        returns (bool success, bytes memory preOpsData)
    {
        preOpsData = abi.encodeCall(IExecutionEnvironment.preOpsWrapper, userOp);
        preOpsData = abi.encodePacked(preOpsData, lockBytes);
        (success, preOpsData) = environment.call(preOpsData);
        if (success) {
            preOpsData = abi.decode(preOpsData, (bytes));
        }
    }

    /// @notice Executes the user operation logic defined in the Execution Environment.
    /// @param userOp UserOperation struct containing the user's transaction data.
    /// @param environment Address of the execution environment where the user operation will be executed.
    /// @param lockBytes Packed bytes form of the current escrow lock state, encoded from the EscrowKey struct.
    /// @return success Boolean indicating whether the UserOperation was executed successfully.
    /// @return userData Data returned from executing the UserOperation, if the call was successful.
    function _executeUserOperation(
        UserOperation calldata userOp,
        address environment,
        bytes memory lockBytes
    )
        internal
        returns (bool success, bytes memory userData)
    {
        userData = abi.encodeCall(IExecutionEnvironment.userWrapper, userOp);
        userData = abi.encodePacked(userData, lockBytes);

        (success, userData) = environment.call{ value: userOp.value }(userData);

        if (success) {
            userData = abi.decode(userData, (bytes));
        }
    }

    /// @notice Attempts to execute a SolverOperation and determine if it wins the auction.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct containing the user's transaction data relevant to this SolverOperation.
    /// @param solverOp SolverOperation struct containing the solver's bid and execution data.
    /// @param dAppReturnData Data returned from UserOp execution, used as input if necessary.
    /// @param bidAmount The amount of bid submitted by the solver for this operation.
    /// @param prevalidated Boolean flag indicating whether the SolverOperation has been prevalidated to skip certain
    /// checks for efficiency.
    /// @param key EscrowKey struct containing the current state of the escrow lock.
    /// @return auctionWon Boolean indicating whether the SolverOperation was successful and won the auction.
    /// @return key Updated EscrowKey struct, reflecting the new state after attempting the SolverOperation.
    function _executeSolverOperation(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        uint256 bidAmount,
        bool prevalidated,
        EscrowKey memory key
    )
        internal
        returns (bool, EscrowKey memory)
    {
        // Set the gas baseline
        uint256 gasWaterMark = gasleft();
        uint256 result;
        if (!prevalidated) {
            result = IAtlasVerification(VERIFICATION).verifySolverOp(
                solverOp, key.userOpHash, userOp.maxFeePerGas, key.bundler
            );
            result = _checkSolverBidToken(solverOp.bidToken, dConfig.bidToken, result);
        }

        // Verify the transaction.
        if (result.canExecute()) {
            uint256 gasLimit;
            // Verify gasLimit again
            (result, gasLimit) = _validateSolverOperation(dConfig, solverOp, gasWaterMark, result);

            if (dConfig.callConfig.allowsTrustedOpHash()) {
                if (!prevalidated && !_handleAltOpHash(userOp, solverOp)) {
                    key.solverOutcome = uint24(result);
                    return (false, key);
                }
            }

            // If there are no errors, attempt to execute
            if (result.canExecute() && _trySolverLock(solverOp)) {
                // Open the solver lock
                key = key.holdSolverLock(solverOp.solver);

                // Execute the solver call
                // _solverOpsWrapper returns a SolverOutcome enum value
                result |= _solverOpWrapper(
                    bidAmount, gasLimit, key.executionEnvironment, solverOp, dAppReturnData, key.pack()
                );

                key.solverOutcome = uint24(result);

                if (result.executionSuccessful()) {
                    // first successful solver call that paid what it bid

                    emit SolverTxResult(solverOp.solver, solverOp.from, true, true, result);

                    key.solverSuccessful = true;
                    // auctionWon = true
                    return (true, key);
                }
            }
        }

        key.solverOutcome = uint24(result);

        _releaseSolverLock(solverOp, gasWaterMark, result, false, !prevalidated);

        unchecked {
            ++key.callIndex;
        }
        // emit event
        emit SolverTxResult(solverOp.solver, solverOp.from, result.executedWithError(), false, result);

        // auctionWon = false
        return (false, key);
    }

    /// @notice Allocates the winning bid amount after a successful SolverOperation execution.
    /// @dev This function handles the allocation of the bid amount to the appropriate recipients as defined in the
    /// DApp's configuration. It calls the allocateValue function in the Execution Environment, which is responsible for
    /// distributing the bid amount. Note that balance discrepancies leading to payment failures are typically due to
    /// issues in the DAppControl contract, not the execution environment itself.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param solverOp SolverOperation struct containing the solver's bid and execution data.
    /// @param winningBidAmount The winning solver's bid amount, to be allocated.
    /// @param returnData Data returned from the execution of the UserOperation, which may influence how the bid amount
    /// is allocated.
    /// @param key EscrowKey struct containing the current state of the escrow lock.
    /// @return key Updated EscrowKey struct, reflecting any changes to the escrow lock state as a result of bid
    /// allocation.
    function _allocateValue(
        DAppConfig calldata dConfig,
        SolverOperation calldata solverOp,
        uint256 winningBidAmount,
        bytes memory returnData,
        EscrowKey memory key
    )
        internal
        returns (EscrowKey memory)
    {
        // process dApp payments
        key = key.holdAllocateValueLock(solverOp.from);

        bytes memory data =
            abi.encodeCall(IExecutionEnvironment.allocateValue, (dConfig.bidToken, winningBidAmount, returnData));
        data = abi.encodePacked(data, key.pack());
        (bool success,) = key.executionEnvironment.call(data);
        if (success) {
            key.paymentsSuccessful = true;
        }

        return key;
    }

    /// @notice Executes post-operation logic after SolverOperation, depending on the outcome of the auction.
    /// @dev Calls the postOpsWrapper function in the Execution Environment, which handles any necessary cleanup or
    /// finalization logic after the winning SolverOperation.
    /// @param solved Boolean indicating whether a SolverOperation was successful and won the auction.
    /// @param returnData Data returned from execution of the UserOp call, which may be required for the postOps logic.
    /// @param key EscrowKey struct containing the current state of the escrow lock.
    /// @return success Boolean indicating whether the postOps logic was executed successfully.
    function _executePostOpsCall(
        bool solved,
        bytes memory returnData,
        EscrowKey memory key
    )
        internal
        returns (bool success)
    {
        bytes memory postOpsData = abi.encodeCall(IExecutionEnvironment.postOpsWrapper, (solved, returnData));
        postOpsData = abi.encodePacked(postOpsData, key.pack());
        (success,) = key.executionEnvironment.call(postOpsData);
    }

    /// @notice Validates a SolverOperation's gas requirements and deadline against the current block and escrow state.
    /// @dev Performs a series of checks to ensure that a SolverOperation can be executed within the defined parameters
    /// and limits. This includes verifying that the operation is within the gas limit, that the current block is before
    /// the operation's deadline, and that the solver has sufficient balance in escrow to cover the gas costs.
    /// @param dConfig DApp configuration data, including solver gas limits and operation parameters.
    /// @param solverOp The SolverOperation being validated.
    /// @param gasWaterMark The initial gas measurement before validation begins, used to ensure enough gas remains for
    /// validation logic.
    /// @param result The current validation result flags, to which new validation results will be bitwise OR'd.
    /// @return Updated result flags after performing the validation checks, including any new errors encountered.
    /// @return gasLimit The calculated gas limit for the SolverOperation, considering the operation's gas usage and
    /// the protocol's gas buffers.
    function _validateSolverOperation(
        DAppConfig calldata dConfig,
        SolverOperation calldata solverOp,
        uint256 gasWaterMark,
        uint256 result
    )
        internal
        view
        returns (uint256, uint256 gasLimit)
    {
        if (gasWaterMark < _VALIDATION_GAS_LIMIT + dConfig.solverGasLimit) {
            // Make sure to leave enough gas for dApp validation calls
            return (result | 1 << uint256(SolverOutcome.UserOutOfGas), gasLimit); // gasLimit = 0
        }

        if (block.number > solverOp.deadline) {
            return (
                result
                    | 1
                        << uint256(
                            dConfig.callConfig.allowsTrustedOpHash()
                                ? uint256(SolverOutcome.DeadlinePassedAlt)
                                : uint256(SolverOutcome.DeadlinePassed)
                        ),
                gasLimit // gasLimit = 0
            );
        }

        gasLimit = _SOLVER_GAS_LIMIT_SCALE
            * (solverOp.gas < dConfig.solverGasLimit ? solverOp.gas : dConfig.solverGasLimit)
            / (_SOLVER_GAS_LIMIT_SCALE + _SOLVER_GAS_LIMIT_BUFFER_PERCENTAGE) + _FASTLANE_GAS_BUFFER;

        uint256 gasCost = (tx.gasprice * gasLimit) + _getCalldataCost(solverOp.data.length);

        // Verify that we can lend the solver their tx value
        if (
            solverOp.value
                > address(this).balance - (gasLimit * tx.gasprice > address(this).balance ? 0 : gasLimit * tx.gasprice)
        ) {
            return (result |= 1 << uint256(SolverOutcome.CallValueTooHigh), gasLimit);
        }

        // subtract out the gas buffer since the solver's metaTx won't use it
        gasLimit -= _FASTLANE_GAS_BUFFER;

        EscrowAccountAccessData memory aData = accessData[solverOp.from];

        uint256 solverBalance = aData.bonded;
        uint256 lastAccessedBlock = aData.lastAccessedBlock;

        // NOTE: Turn this into time stamp check for FCFS L2s?
        if (lastAccessedBlock == block.number) {
            result |= 1 << uint256(SolverOutcome.PerBlockLimit);
        }

        // see if solver's escrow can afford tx gascost
        if (gasCost > solverBalance) {
            // charge solver for calldata so that we can avoid vampire attacks from solver onto user
            result |= 1 << uint256(SolverOutcome.InsufficientEscrow);
        }

        return (result, gasLimit);
    }

    /// @notice Determines the bid amount for a SolverOperation based on verification and validation results.
    /// @dev This function assesses whether a SolverOperation meets the criteria for execution by verifying it against
    /// the Atlas protocol's rules and the current EscrowKey lock state. It checks for valid execution based on the
    /// SolverOperation's specifics, like gas usage and deadlines. The function aims to protect against malicious
    /// bundlers by ensuring solvers are not unfairly charged for on-chain bid finding gas usage. If the operation
    /// passes verification and validation, and if it's eligible for bid amount determination, the function attempts to
    /// execute and determine the bid amount.
    /// @param dConfig DApp configuration data, including parameters relevant to solver bid validation.
    /// @param userOp The UserOperation associated with this SolverOperation, providing context for the bid amount
    /// determination.
    /// @param solverOp The SolverOperation being assessed, containing the solver's bid amount.
    /// @param data Data returned from execution of the UserOp call, passed to the execution environment's
    /// solverMetaTryCatch function for execution.
    /// @param key EscrowKey struct containing the current state of the escrow lock.
    /// @return bidAmount The determined bid amount for the SolverOperation if all validations pass and the operation is
    /// executed successfully; otherwise, returns 0.
    function _getBidAmount(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        bytes memory data,
        EscrowKey memory key
    )
        internal
        returns (uint256 bidAmount)
    {
        // NOTE: To prevent a malicious bundler from aggressively collecting storage refunds,
        // solvers should not be on the hook for any 'on chain bid finding' gas usage.

        bool success;
        uint256 gasWaterMark = gasleft();

        uint256 result =
            IAtlasVerification(VERIFICATION).verifySolverOp(solverOp, key.userOpHash, userOp.maxFeePerGas, key.bundler);

        result = _checkSolverBidToken(solverOp.bidToken, dConfig.bidToken, result);

        // Verify the transaction.
        if (!result.canExecute()) return 0;

        uint256 gasLimit;
        (result, gasLimit) = _validateSolverOperation(dConfig, solverOp, gasWaterMark, result);

        if (dConfig.callConfig.allowsTrustedOpHash()) {
            if (!_handleAltOpHash(userOp, solverOp)) {
                return (0);
            }
        }

        // If there are no errors, attempt to execute
        if (!result.canExecute() || !_trySolverLock(solverOp)) return 0;

        data = abi.encodeCall(IExecutionEnvironment.solverMetaTryCatch, (solverOp.bidAmount, gasLimit, solverOp, data));

        data = abi.encodePacked(data, key.holdSolverLock(solverOp.solver).pack());

        (success, data) = key.executionEnvironment.call{ value: solverOp.value }(data);

        _releaseSolverLock(solverOp, gasWaterMark, result, true, true);

        if (success) {
            revert();
        }

        if (bytes4(data) == BidFindSuccessful.selector) {
            // Get the uint256 from the memory array
            assembly {
                let dataLocation := add(data, 0x20)
                bidAmount :=
                    mload(
                        add(
                            dataLocation,
                            sub(mload(data), 32) // TODO: make sure a full uint256 is safe from overflow
                        )
                    )
            }
            return bidAmount;
        } else {
            return 0;
        }
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
        if (solverOp.deadline != userOp.deadline || solverOp.control != userOp.control) {
            return false;
        }
        bytes32 hashId = keccak256(abi.encodePacked(solverOp.userOpHash, solverOp.from, solverOp.deadline));
        if (_solverOpHashes[hashId]) {
            return false;
        }
        _solverOpHashes[hashId] = true;
        return true;
    }

    // NOTE: This logic should be inside `verifySolverOp()` in AtlasVerification, but we hit Stack Too Deep errors when
    // trying to do this check there, as an additional param (dConfig.bidToken) is needed. This logic should be moved to
    // that function when a larger refactor is done to get around Stack Too Deep.
    function _checkSolverBidToken(
        address solverBidToken,
        address dConfigBidToken,
        uint256 result
    )
        internal
        view
        returns (uint256)
    {
        if (solverBidToken != dConfigBidToken) {
            return result | 1 << uint256(SolverOutcome.InvalidBidToken);
        }
        return result;
    }

    /// @notice Wraps the execution of a SolverOperation and handles potential errors.
    /// @param bidAmount The bid amount associated with the SolverOperation.
    /// @param gasLimit The gas limit for executing the SolverOperation, calculated based on the operation's
    /// requirements and protocol buffers.
    /// @param environment The execution environment address where the SolverOperation will be executed.
    /// @param solverOp The SolverOperation struct containing the operation's execution data.
    /// @param dAppReturnData Data returned from the execution of the associated UserOperation, which may be required
    /// for the SolverOperation's logic.
    /// @param lockBytes The packed bytes form of the current EscrowKey state.
    /// @return A SolverOutcome enum value encoded as a uint256 bitmap, representing the result of the SolverOperation
    function _solverOpWrapper(
        uint256 bidAmount,
        uint256 gasLimit,
        address environment,
        SolverOperation calldata solverOp,
        bytes memory dAppReturnData,
        bytes memory lockBytes
    )
        internal
        returns (uint256)
    {
        bool success;
        bytes memory data =
            abi.encodeCall(IExecutionEnvironment.solverMetaTryCatch, (bidAmount, gasLimit, solverOp, dAppReturnData));

        data = abi.encodePacked(data, lockBytes);

        (success, data) = environment.call{ value: solverOp.value }(data);

        if (success) {
            return uint256(0);
        }
        bytes4 errorSwitch = bytes4(data);

        if (errorSwitch == AlteredControl.selector) {
            return 1 << uint256(SolverOutcome.AlteredControl);
        } else if (errorSwitch == PreSolverFailed.selector) {
            return 1 << uint256(SolverOutcome.PreSolverFailed);
        } else if (errorSwitch == SolverOperationReverted.selector) {
            return 1 << uint256(SolverOutcome.SolverOpReverted);
        } else if (errorSwitch == PostSolverFailed.selector) {
            return 1 << uint256(SolverOutcome.PostSolverFailed);
        } else if (errorSwitch == IntentUnfulfilled.selector) {
            return 1 << uint256(SolverOutcome.IntentUnfulfilled);
        } else if (errorSwitch == SolverBidUnpaid.selector) {
            return 1 << uint256(SolverOutcome.BidNotPaid);
        } else if (errorSwitch == BalanceNotReconciled.selector) {
            return 1 << uint256(SolverOutcome.BalanceNotReconciled);
        } else if (errorSwitch == InvalidEntry.selector) {
            // DAppControl is attacking solver contract - treat as AlteredControl
            return 1 << uint256(SolverOutcome.AlteredControl);
        } else if (errorSwitch == CallbackNotCalled.selector) {
            return 1 << uint256(SolverOutcome.SolverOpReverted);
        } else {
            return 1 << uint256(SolverOutcome.EVMError);
        }
    }

    receive() external payable { }

    fallback() external payable {
        revert();
    }
}
