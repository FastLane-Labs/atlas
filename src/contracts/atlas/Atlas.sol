//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibSort } from "solady/utils/LibSort.sol";

import { IDAppControl } from "../interfaces/IDAppControl.sol";

import { Escrow } from "./Escrow.sol";
import { Factory } from "./Factory.sol";

import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/DAppOperation.sol";
import "src/contracts/types/ValidCalls.sol";

import { CallBits } from "src/contracts/libraries/CallBits.sol";
import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";

/// @title Atlas V1
/// @author FastLane Labs
/// @notice The Execution Abstraction protocol.
contract Atlas is Escrow, Factory {
    using CallBits for uint32;
    using SafetyBits for Context;

    constructor(
        uint256 escrowDuration,
        address verification,
        address simulator,
        address surchargeRecipient,
        address executionTemplate
    )
        Escrow(escrowDuration, verification, simulator, surchargeRecipient)
        Factory(executionTemplate)
    { }

    /// @notice metacall is the entrypoint function for the Atlas transactions.
    /// @param userOp The UserOperation struct containing the user's transaction data.
    /// @param solverOps The SolverOperation array containing the solvers' transaction data.
    /// @param dAppOp The DAppOperation struct containing the DApp's transaction data.
    /// @return auctionWon A boolean indicating whether there was a successful, winning solver.
    function metacall(
        UserOperation calldata userOp, // set by user
        SolverOperation[] calldata solverOps, // supplied by ops relay
        DAppOperation calldata dAppOp // supplied by front end via atlas SDK
    )
        external
        payable
        returns (bool auctionWon)
    {
        uint256 _gasMarker = gasleft() + 21_000 + (msg.data.length * _CALLDATA_LENGTH_PREMIUM);
        bool _isSimulation = msg.sender == SIMULATOR;

        (address _executionEnvironment, DAppConfig memory _dConfig) = _getOrCreateExecutionEnvironment(userOp);

        // Gracefully return if not valid. This allows signature data to be stored, which helps prevent
        // replay attacks.
        // NOTE: Currently reverting instead of graceful return to help w/ testing. TODO - still reverting?
        ValidCallsResult _validCallsResult =
            VERIFICATION.validateCalls(_dConfig, userOp, solverOps, dAppOp, msg.value, msg.sender, _isSimulation);
        if (_validCallsResult != ValidCallsResult.Valid) {
            if (_isSimulation) revert VerificationSimFail(_validCallsResult);
            revert ValidCalls(_validCallsResult);
        }

        // Initialize the environment lock and accounting values
        _setEnvironmentLock(_dConfig, _executionEnvironment);
        _initializeAccountingValues(_gasMarker);

        // userOpHash has already been calculated and verified in validateCalls at this point, so rather
        // than re-calculate it, we can simply take it from the dAppOp here. It's worth noting that this will
        // be either a TRUSTED or DEFAULT hash, depending on the allowsTrustedOpHash setting.
        try this.execute(_dConfig, userOp, solverOps, _executionEnvironment, msg.sender, dAppOp.userOpHash) returns (
            Context memory ctx
        ) {
            // Gas Refund to sender only if execution is successful
            (uint256 _ethPaidToBundler, uint256 _netGasSurcharge) = _settle(ctx, _dConfig.solverGasLimit);

            auctionWon = ctx.solverSuccessful;
            emit MetacallResult(
                msg.sender, userOp.from, auctionWon, ctx.paymentsSuccessful, _ethPaidToBundler, _netGasSurcharge
            );
        } catch (bytes memory revertData) {
            // Bubble up some specific errors
            _handleErrors(revertData, _dConfig.callConfig);

            // Refund the msg.value to sender if it errored
            // WARNING: If msg.sender is a disposable address such as a session key, make sure to remove ETH from it
            // before disposal
            if (msg.value != 0) SafeTransferLib.safeTransferETH(msg.sender, msg.value);
        }

        // Release the lock
        _releaseAccountingLock();
    }

    /// @notice execute is called above, in a try-catch block in metacall.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @param solverOps SolverOperation array of the current metacall tx.
    /// @param executionEnvironment Address of the execution environment contract of the current metacall tx.
    /// @param bundler Address of the bundler of the current metacall tx.
    /// @param userOpHash Hash of the userOp struct of the current metacall tx.
    /// @return ctx Context struct containing relavent context information for the Atlas auction.
    function execute(
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        address executionEnvironment,
        address bundler,
        bytes32 userOpHash
    )
        external
        payable
        returns (Context memory ctx)
    {
        // This is a self.call made externally so that it can be used with try/catch
        if (msg.sender != address(this)) revert InvalidAccess();

        // Build the context object
        ctx = _buildContext(
            dConfig, executionEnvironment, userOpHash, bundler, uint8(solverOps.length), bundler == SIMULATOR
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
        if (ctx.solverSuccessful) {
            _allocateValue(ctx, dConfig, _winningBidAmount, _returnData);
        }

        // PostOp Call
        if (dConfig.callConfig.needsPostOpsCall()) {
            _executePostOpsCall(ctx, ctx.solverSuccessful, _returnData);
        }
    }

    /// @notice Called above in `execute` if the DAppConfig requires ex post bids. Sorts solverOps by bid amount and
    /// executes them in descending order until a successful winner is found.
    /// @param ctx Context struct containing the current state of the escrow lock.
    /// @param dConfig Configuration data for the DApp involved, containing execution parameters and settings.
    /// @param userOp UserOperation struct of the current metacall tx.
    /// @param solverOps SolverOperation array of the current metacall tx.
    /// @param returnData Return data from the preOps and userOp calls.
    /// @return The winning bid amount.
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
        // Return early if no solverOps (e.g. in simUserOperation)
        if (solverOps.length == 0) {
            if (ctx.isSimulation) revert SolverSimFail(0);
            if (dConfig.callConfig.needsFulfillment()) revert UserNotFulfilled();
            return 0;
        }

        ctx.bidFind = true;

        uint256[] memory _bidsAndIndices = new uint256[](solverOps.length);
        uint256 _zeroBidCount;
        uint256 _bidAmountFound;
        uint256 _bidsAndIndicesLastIndex = _bidsAndIndices.length - 1; // computed once for efficiency

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

        for (uint256 i; i < solverOps.length; ++i) {
            _bidAmountFound = _getBidAmount(ctx, dConfig, userOp, solverOps[i], returnData);

            if (_bidAmountFound == 0 || _bidAmountFound > type(uint240).max) {
                // Zero bids are ignored: increment _zeroBidCount offset
                // Bids that would cause an overflow are also ignored
                unchecked {
                    ++_zeroBidCount;
                }
            } else {
                // Non-zero bids are packed with their original solverOps index.
                // The array is filled with non-zero bids from the right. This causes all zero bids to be on the left -
                // in their sorted position, so fewer operations are needed in the sorting step below.
                _bidsAndIndices[_bidsAndIndicesLastIndex - (i - _zeroBidCount)] =
                    uint256(_bidAmountFound << _BITS_FOR_INDEX | uint16(i));
            }
        }

        // Then, sorts the uint256 array in-place, in ascending order.
        LibSort.insertionSort(_bidsAndIndices);

        ctx.bidFind = false;

        // Finally, iterate through sorted bidsAndIndices array in descending order of bidAmount.
        for (uint256 i = _bidsAndIndicesLastIndex; i >= 0; --i) {
            // Isolate the bidAmount from the packed uint256 value
            _bidAmountFound = (_bidsAndIndices[i] >> _BITS_FOR_INDEX) & _FIRST_240_BITS_TRUE_MASK;

            // If we reach the zero bids on the left of array, break as all valid bids already checked.
            if (_bidAmountFound == 0) break;

            // Isolate the original solverOps index from the packed uint256 value
            uint256 _solverIndex = uint8(_bidsAndIndices[i] & _FIRST_16_BITS_TRUE_MASK);
            ctx.solverIndex = uint8(_solverIndex); // Yay, compiler <3

            // Execute the solver operation. If solver won, allocate value and return. Otherwise continue looping.
            _bidAmountFound = _executeSolverOperation(
                ctx, dConfig, userOp, solverOps[_solverIndex], _bidAmountFound, true, returnData
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
    /// @return The winning bid amount.
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

        for (uint8 i = uint8(solverOps.length); ctx.solverIndex < i; ctx.solverIndex++) {
            SolverOperation calldata solverOp = solverOps[ctx.solverIndex];

            _bidAmount = _executeSolverOperation(ctx, dConfig, userOp, solverOp, solverOp.bidAmount, false, returnData);

            if (ctx.solverSuccessful) {
                return _bidAmount;
            }
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
            // Simulation
            if (_errorSwitch == PreOpsSimFail.selector) {
                revert PreOpsSimFail();
            } else if (_errorSwitch == UserOpSimFail.selector) {
                revert UserOpSimFail();
            } else if (_errorSwitch == SolverSimFail.selector) {
                // Expects revertData in form [bytes4, uint256]
                uint256 _solverOutcomeResult;
                assembly {
                    let dataLocation := add(revertData, 0x20)
                    _solverOutcomeResult := mload(add(dataLocation, sub(mload(revertData), 32)))
                }
                revert SolverSimFail(_solverOutcomeResult);
            } else if (_errorSwitch == AllocateValueSimFail.selector) {
                revert AllocateValueSimFail();
            } else if (_errorSwitch == PostOpsSimFail.selector) {
                revert PostOpsSimFail();
            }
        }
        if (_errorSwitch == UserNotFulfilled.selector) {
            revert UserNotFulfilled();
        }
        // If allowReuseUserOps = true, it reverts and bubbles up whatever the error
        // was that it caught. This is to prevent storing the nonce as used so the userOp
        // can be reused. Otherwise, the whole metacall doesn't revert but the inner
        // execute() does so, no operation changes are persisted.
        if (callConfig.allowsReuseUserOps()) {
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
        view
        override
        returns (bool)
    {
        return environment == _getExecutionEnvironmentCustom(user, control, callConfig);
    }
}
