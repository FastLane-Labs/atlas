//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibSort } from "solady/utils/LibSort.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { Escrow } from "./Escrow.sol";
import { Factory } from "./Factory.sol";

import "../types/SolverOperation.sol";
import "../types/UserOperation.sol";
import "../types/LockTypes.sol";
import "../types/ConfigTypes.sol";
import "../types/DAppOperation.sol";
import "../types/ValidCalls.sol";

import { CallBits } from "../libraries/CallBits.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol";
import { GasAccLib, GasLedger } from "../libraries/GasAccLib.sol";
import { IL2GasCalculator } from "../interfaces/IL2GasCalculator.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";

/// @title Atlas V1.5
/// @author FastLane Labs
/// @notice The Execution Abstraction protocol.
contract Atlas is Escrow, Factory {
    using CallBits for uint32;
    using SafetyBits for Context;
    using GasAccLib for uint256;
    using GasAccLib for GasLedger;

    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator,
        address factoryLib
    )
        Escrow(escrowDuration, atlasSurchargeRate, verification, simulator, initialSurchargeRecipient, l2GasCalculator)
        Factory(factoryLib)
    { }

    /// @notice metacall is the entrypoint function for the Atlas transactions.
    /// @dev Any ETH sent as msg.value with a metacall should be considered a potential subsidy for the winning solver's
    /// gas repayment.
    /// @param userOp The UserOperation struct containing the user's transaction data.
    /// @param solverOps The SolverOperation array containing the solvers' transaction data.
    /// @param dAppOp The DAppOperation struct containing the DApp's transaction data.
    /// @param gasRefundBeneficiary The address to receive the gas refund.
    /// @return auctionWon A boolean indicating whether there was a successful, winning solver.
    function metacall(
        UserOperation calldata userOp, // set by user
        SolverOperation[] calldata solverOps, // supplied by ops relay
        DAppOperation calldata dAppOp, // supplied by front end via atlas SDK
        address gasRefundBeneficiary // address(0) = msg.sender
    )
        external
        payable
        returns (bool auctionWon)
    {
        // _gasMarker calculated as (Execution gas cost) + (Calldata gas cost). Any gas left at the end of the metacall
        // is deducted from this _gasMarker, resulting in actual execution gas used + calldata gas costs + buffer.
        // The calldata component is added below, only if exPostBids = false.
        uint256 _gasLeft = gasleft();
        uint256 _gasMarker = _gasLeft + _BASE_TX_GAS_USED + FIXED_GAS_OFFSET; // This part is only execution gas.

        DAppConfig memory _dConfig;
        bool _isSimulation = msg.sender == SIMULATOR;
        address _executionEnvironment;
        address _bundler = _isSimulation ? dAppOp.bundler : msg.sender;
        (_executionEnvironment, _dConfig) = _getOrCreateExecutionEnvironment(userOp);

        // Validate metacall params, and get back vars used in gas accounting logic
        (
            uint256 _allSolversGasLimit,
            uint256 _allSolversCalldataGas,
            uint256 _bidFindOverhead,
            ValidCallsResult _validCallsResult
        ) = VERIFICATION.validateCalls({
            dConfig: _dConfig,
            userOp: userOp,
            solverOps: solverOps,
            dAppOp: dAppOp,
            metacallGasLeft: _gasLeft,
            msgValue: msg.value,
            msgSender: _bundler,
            isSimulation: _isSimulation
        });

        // Solvers pay for calldata when exPostBids = false
        if (!_dConfig.callConfig.exPostBids()) {
            // total calldata gas = solver calldata gas + (userOp + dAppOp + offset) calldata gas
            _gasMarker += _allSolversCalldataGas
                + GasAccLib.metacallCalldataGas(
                    userOp.data.length + USER_OP_STATIC_LENGTH + DAPP_OP_LENGTH + _EXTRA_CALLDATA_LENGTH, L2_GAS_CALCULATOR
                );
        }

        // Handle the ValidCallsResult
        if (_validCallsResult != ValidCallsResult.Valid) {
            if (_isSimulation) revert VerificationSimFail(_validCallsResult);

            // Gracefully return for results that need nonces to be stored and prevent replay attacks
            if (uint8(_validCallsResult) >= _GRACEFUL_RETURN_THRESHOLD && !_dConfig.callConfig.allowsReuseUserOps()) {
                return false;
            }

            // Revert for all other results
            revert ValidCalls(_validCallsResult);
        }

        // Initialize the environment lock and accounting values
        _setEnvironmentLock(_dConfig, _executionEnvironment);

        // _gasMarker - _bidFindOverhead = estimated winning solver gas liability (not charged for bid-find gas)
        // userOp.bundlerSurchargeRate is checked against the value set in the DAppControl in `validateCalls()` above
        _initializeAccountingValues({
            gasMarker: _gasMarker - _bidFindOverhead,
            allSolverOpsGas: _allSolversGasLimit,
            bundlerSurchargeRate: userOp.bundlerSurchargeRate
        });

        // Calculate `execute` gas limit such that it can fail due to an OOG error caused by any of the hook calls, and
        // the metacall will still have enough gas to gracefully finish and return, storing any nonces required.
        uint256 _gasLimit = gasleft() * 63 / 64 - _GRACEFUL_RETURN_GAS_OFFSET;

        // userOpHash has already been calculated and verified in validateCalls at this point, so rather
        // than re-calculate it, we can simply take it from the dAppOp here. It's worth noting that this will
        // be either a TRUSTED or DEFAULT hash, depending on the allowsTrustedOpHash setting.
        try this.execute{ gas: _gasLimit }(
            _dConfig, userOp, solverOps, dAppOp.userOpHash, _executionEnvironment, _bundler, _isSimulation
        ) returns (Context memory ctx) {
            GasLedger memory _gL = t_gasLedger.toGasLedger(); // Final load, no need to persist changes after this
            uint256 _unreachedCalldataValuePaid;

            // Only charge unreached solverOps for their calldata if NOT in exPostBids mode
            if (!_dConfig.callConfig.exPostBids()) {
                _unreachedCalldataValuePaid = _chargeUnreachedSolversForCalldata(
                    solverOps,
                    _gL,
                    ctx.solverIndex,
                    dAppOp.userOpHash,
                    userOp.maxFeePerGas,
                    _bundler,
                    _dConfig.callConfig.allowsTrustedOpHash()
                );
            }

            // Gas Refund to sender only if execution is successful, or if multipleSuccessfulSolvers
            (uint256 _ethPaidToBundler, uint256 _netGasSurcharge) = _settle(
                ctx,
                _gL,
                _gasMarker,
                gasRefundBeneficiary,
                _unreachedCalldataValuePaid,
                _dConfig.callConfig.multipleSuccessfulSolvers()
            );

            auctionWon = ctx.solverSuccessful;
            emit MetacallResult(msg.sender, userOp.from, auctionWon, _ethPaidToBundler, _netGasSurcharge);
        } catch (bytes memory revertData) {
            // Bubble up some specific errors
            _handleErrors(revertData, _dConfig.callConfig);
            // Set lock to FullyLocked to prevent any reentrancy possibility
            _setLockPhase(uint8(ExecutionPhase.FullyLocked));

            // Refund the msg.value to sender if it errored
            // WARNING: If msg.sender is a disposable address such as a session key, make sure to remove ETH from it
            // before disposal
            if (msg.value != 0) SafeTransferLib.safeTransferETH(msg.sender, msg.value);

            // Emit event indicating the metacall failed in `execute()`
            emit MetacallResult(msg.sender, userOp.from, false, 0, 0);
        }

        // The environment lock is explicitly released here to allow multiple (sequential, not nested) metacalls in a
        // single transaction.
        _releaseLock();
    }

    /// @notice execute is called above, in a try-catch block in metacall.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @param solverOps SolverOperation array of the current metacall tx.
    /// @param userOpHash The hash of the UserOperation.
    /// @param executionEnvironment The address of the execution environment.
    /// @param bundler The address of the bundler.
    /// @param isSimulation Whether the current execution is a simulation.
    /// @return ctx Context struct containing relevant context information for the Atlas auction.
    function execute(
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        bytes32 userOpHash,
        address executionEnvironment,
        address bundler,
        bool isSimulation
    )
        external
        payable
        returns (Context memory ctx)
    {
        // This is a self.call made externally so that it can be used with try/catch
        if (msg.sender != address(this)) revert InvalidAccess();

        // Build the context object
        ctx = _buildContext(
            userOpHash, executionEnvironment, bundler, dConfig.dappGasLimit, uint8(solverOps.length), isSimulation
        );

        bytes memory _returnData;

        // PreOps Call
        if (dConfig.callConfig.needsPreOpsCall()) {
            _returnData = _executePreOpsCall(ctx, dConfig, userOp);
        }

        // UserOp Call
        _returnData = _executeUserOperation(ctx, dConfig, userOp, _returnData);

        // SolverOps Calls
        uint256 _winningBidAmount = dConfig.callConfig.exPostBids()
            ? _bidFindingIteration(ctx, dConfig, userOp, solverOps, _returnData)
            : _bidKnownIteration(ctx, dConfig, userOp, solverOps, _returnData);

        // AllocateValue Call
        _allocateValue(ctx, dConfig, _winningBidAmount, _returnData);
    }

    /// @notice Called above in `execute` if the DAppConfig requires ex post bids. Sorts solverOps by bid amount and
    /// executes them in descending order until a successful winner is found.
    /// @param ctx Context struct containing the current state of the escrow lock.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @param solverOps SolverOperation array of the current metacall tx.
    /// @param returnData Return data from the preOps and userOp calls.
    /// @return The winning bid amount or 0 when no solverOps.
    function _bidFindingIteration(
        Context memory ctx,
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        bytes memory returnData
    )
        internal
        returns (uint256)
    {
        uint256 _gasWaterMark = gasleft(); // track bid-finding gas, to be written off.
        uint256 solverOpsLength = solverOps.length; // computed once for efficiency

        // Return early if no solverOps (e.g. in simUserOperation)
        if (solverOpsLength == 0) {
            if (ctx.isSimulation) revert SolverSimFail(0);
            if (dConfig.callConfig.needsFulfillment()) revert UserNotFulfilled();
            return 0;
        }

        ctx.bidFind = true;

        uint256[] memory _bidsAndIndices = new uint256[](solverOpsLength);
        uint256 _bidAmountFound;
        uint256 _solverExecutionGas;
        uint256 _bidsAndIndicesLastIndex = solverOpsLength - 1; // Start from the last index

        // Get a snapshot of the GasLedger from transient storage, to reset to after bid-finding below
        uint256 _gasLedgerSnapshot = t_gasLedger;

        // First, get all bid amounts. Bids of zero are ignored by only storing non-zero bids in the array, from right
        // to left. If there are any zero bids they will end up on the left as uint(0) values - in their sorted
        // position. This reduces operations needed later when sorting the array in ascending order.
        // Each non-zero bid amount is packed with its original solverOps array index, to fit into a uint256 value. The
        // order of bidAmount and index is important - with bidAmount using the most significant bits, and considering
        // we do not store zero bids in the array, the index values within the uint256 should not impact the sorting.

        // |<------------------------- uint256 (256 bits) ------------------------->|
        // |                                                                        |
        // |<------------------ uint240 ----------------->|<-------- uint16 ------->|
        // |                                              |                         |
        // |                    bidAmount                 |          index          |
        // |                                              |                         |
        // |<------------------ 240 bits ---------------->|<------- 16 bits ------->|

        for (uint256 i; i < solverOpsLength; ++i) {
            _bidAmountFound = _getBidAmount(ctx, dConfig, userOp, solverOps[i], returnData);

            // In `_getBidAmount()` above, unreachedSolverGas is decreased while remainingMaxGas does not change, as it
            // is normally decreased in `_handleSolverFailAccounting()` which is not called in a bid-finding context. To
            // adjust for this difference so GasLedger.solverGasLiability() still works, we have to decrease
            // remainingMaxGas separately here. This decrease does not include calldata gas as solvers are not charged
            // for calldata gas in exPostBids mode.
            GasLedger memory _gL = t_gasLedger.toGasLedger();
            // Deduct solverOp.gas (with a ceiling of dConfig.solverGasLimit) from remainingMaxGas
            _solverExecutionGas = Math.min(solverOps[i].gas, dConfig.solverGasLimit);
            _gL.remainingMaxGas -= uint40(_solverExecutionGas);
            t_gasLedger = _gL.pack();

            // skip zero and overflow bid's
            if (_bidAmountFound != 0 && _bidAmountFound <= type(uint240).max) {
                // Non-zero bids are packed with their original solverOps index.
                // The array is filled with non-zero bids from the right.
                _bidsAndIndices[_bidsAndIndicesLastIndex] = uint256(_bidAmountFound << _BITS_FOR_INDEX | uint16(i));
                unchecked {
                    --_bidsAndIndicesLastIndex;
                }
            }
        }

        // Reset transient GasLedger to its state before the bid-finding loop above
        t_gasLedger = _gasLedgerSnapshot;

        // Reinitialize _bidsAndIndicesLastIndex to iterate through the sorted array in descending order
        _bidsAndIndicesLastIndex = solverOpsLength - 1;

        // Then, sorts the uint256 array in-place, in ascending order.
        LibSort.insertionSort(_bidsAndIndices);

        ctx.bidFind = false;

        // Write off the gas cost involved in on-chain bid-finding execution of all solverOps, as these costs should be
        // paid by the bundler.
        _writeOffBidFindGas(_gasWaterMark - gasleft());

        // Finally, iterate through sorted bidsAndIndices array in descending order of bidAmount.
        for (uint256 i = _bidsAndIndicesLastIndex;; /* breaks when 0 */ --i) {
            // Now, track gas watermark to charge/writeoff gas for each solverOp
            _gasWaterMark = gasleft();

            // Isolate the bidAmount from the packed uint256 value
            _bidAmountFound = _bidsAndIndices[i] >> _BITS_FOR_INDEX;

            // If we reach the zero bids on the left of array, break as all valid bids already checked.
            if (_bidAmountFound == 0) break;

            // NOTE: We reuse the ctx.solverIndex variable to store the count of solver ops that have been executed.
            // This count is useful in `_settle()` when we may penalize the bundler for overestimating gas limit of the
            // metacall tx.
            ctx.solverIndex = uint8(_bidsAndIndicesLastIndex - i);

            // Isolate the original solverOps index from the packed uint256 value
            uint256 _solverIndex = uint8(_bidsAndIndices[i] & _FIRST_16_BITS_TRUE_MASK);

            // Execute the solver operation. If solver won, allocate value and return. Otherwise continue looping.
            _bidAmountFound = _executeSolverOperation(
                ctx, dConfig, userOp, solverOps[_solverIndex], _bidAmountFound, _gasWaterMark, true, returnData
            );

            if (ctx.solverSuccessful) {
                return _bidAmountFound;
            }

            if (i == 0) break; // break to prevent underflow in next loop
        }
        if (ctx.isSimulation) revert SolverSimFail(uint256(ctx.solverOutcome));
        if (dConfig.callConfig.needsFulfillment()) revert UserNotFulfilled();
        return 0;
    }

    /// @notice Called above in `execute` as an alternative to `_bidFindingIteration`, if solverOps have already been
    /// reliably sorted. Executes solverOps in order until a successful winner is found.
    /// @param ctx Context struct containing the current state of the escrow lock.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @param solverOps SolverOperation array of the current metacall tx.
    /// @param returnData Return data from the preOps and userOp calls.
    /// @return The winning bid amount or 0 when no solverOps.
    function _bidKnownIteration(
        Context memory ctx,
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        bytes memory returnData
    )
        internal
        returns (uint256)
    {
        uint256 _bidAmount;

        uint8 solverOpsLen = uint8(solverOps.length);
        for (; ctx.solverIndex < solverOpsLen; ctx.solverIndex++) {
            // track gas watermark to charge/writeoff gas for each solverOp
            uint256 _gasWaterMark = gasleft();

            SolverOperation calldata solverOp = solverOps[ctx.solverIndex];

            // if multipleSuccessfulSolvers = true, solver bids are summed here. Otherwise, 0 bids are returned on
            // solverOp failure, and only the first successful solver's bid is added to `_bidAmount`.
            _bidAmount += _executeSolverOperation(
                ctx, dConfig, userOp, solverOp, solverOp.bidAmount, _gasWaterMark, false, returnData
            );

            // If a winning solver is found, stop iterating through the solverOps and return the winning bid
            if (ctx.solverSuccessful) {
                return _bidAmount;
            }
        }

        // If no winning solver, but multipleSuccessfulSolvers is true, return the sum of solver bid amounts
        if (dConfig.callConfig.multipleSuccessfulSolvers()) {
            // Considered a fail for simulation purposes when only one solverOp in the metacall, and it fails. If more
            // than 1 solverOp, any of them could fail and simulation could still be successful.
            if (ctx.isSimulation && solverOpsLen == 1 && ctx.solverOutcome != 0) {
                revert SolverSimFail(uint256(ctx.solverOutcome));
            }

            return _bidAmount;
        }

        if (ctx.isSimulation) revert SolverSimFail(uint256(ctx.solverOutcome));
        if (dConfig.callConfig.needsFulfillment()) revert UserNotFulfilled();
        return 0;
    }

    /// @notice Called at the end of `metacall` to bubble up specific error info in a revert.
    /// @param revertData Revert data from a failure during the execution of the metacall.
    /// @param callConfig The CallConfig of the current metacall tx.
    function _handleErrors(bytes memory revertData, uint32 callConfig) internal view {
        bytes4 _errorSwitch = bytes4(revertData);

        if (msg.sender == SIMULATOR) {
            if (_errorSwitch == SolverSimFail.selector) {
                // Expects revertData in form [bytes4, uint256]
                uint256 _solverOutcomeResult;
                assembly {
                    let dataLocation := add(revertData, 0x20)
                    _solverOutcomeResult := mload(add(dataLocation, sub(mload(revertData), 32)))
                }
                revert SolverSimFail(_solverOutcomeResult);
            } else if (
                _errorSwitch == PreOpsSimFail.selector || _errorSwitch == UserOpSimFail.selector
                    || _errorSwitch == AllocateValueSimFail.selector
            ) {
                assembly {
                    mstore(0, _errorSwitch)
                    revert(0, 4)
                }
            }
        }

        // NOTE: If error was UserNotFulfilled, we revert and bubble up the error.
        // For any other error, we only bubble up the revert if allowReuseUserOps = true. This is to prevent storing the
        // nonce as used so the userOp can be reused. Otherwise, the whole metacall doesn't revert but the inner
        // execute() does so, no operation changes are persisted.
        if (_errorSwitch == UserNotFulfilled.selector || callConfig.allowsReuseUserOps()) {
            assembly {
                mstore(0, _errorSwitch)
                revert(0, 4)
            }
        }
    }

    /// @notice Returns whether or not the execution environment address matches what's expected from the set of inputs.
    /// @param environment ExecutionEnvironment address
    /// @param user User address
    /// @param control DAppControl contract address
    /// @param callConfig CallConfig of the current metacall tx.
    /// @return A bool indicating whether the execution environment address is the same address that the factory would
    /// deploy an Execution Environment to, given the user, control, and callConfig params.
    function _verifyUserControlExecutionEnv(
        address environment,
        address user,
        address control,
        uint32 callConfig
    )
        internal
        override
        returns (bool)
    {
        return environment == _getExecutionEnvironmentCustom(user, control, callConfig);
    }
}
