//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { DAppOperation } from "src/contracts/types/DAppOperation.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";

// Interface Import
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";
import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";

import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { FastLaneOnlineInner } from "src/contracts/examples/fastlane-online/FastLaneOnlineInner.sol";
import { SolverGateway } from "src/contracts/examples/fastlane-online/SolverGateway.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

contract FastLaneOnlineOuter is SolverGateway {
    constructor(address _atlas) SolverGateway(_atlas) { }

    //////////////////////////////////////////////
    // THIS IS WHAT THE USER INTERACTS THROUGH.
    //////////////////////////////////////////////
    function fastOnlineSwap(UserOperation calldata userOp) external payable withUserLock(msg.sender) onlyAsControl {
        // Calculate the magnitude of the impact of this tx on reputation
        uint256 _repMagnitude = gasleft() * tx.gasprice;

        // Track the gas token balance to repay the swapper with
        uint256 _gasRefundTracker = address(this).balance - msg.value;

        // Get the userOpHash
        bytes32 _userOpHash = IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(userOp);

        // Run gas limit checks on the userOp
        _validateSwap(userOp);

        // Get and sortSolverOperations
        (SolverOperation[] memory _solverOps, uint256 _gasReserved) = _getSolverOps(_userOpHash);
        _solverOps = _sortSolverOps(_solverOps);

        // Build dApp operation
        DAppOperation memory _dAppOp = _getDAppOp(_userOpHash, userOp.deadline);

        // Atlas call
        bool _success;
        bytes memory _data = abi.encodeCall(IAtlas.metacall, (userOp, _solverOps, _dAppOp));
        (_success, _data) =
            ATLAS.call{ value: msg.value, gas: _metacallGasLimit(_gasReserved, userOp.gas, gasleft()) }(_data);

        // Revert if the metacall failed - neither solvers nor baseline call fulfilled swap intent
        if (!_success) revert FLOnlineOuter_FastOnlineSwap_NoFulfillment();

        // Find out if any of the solvers were successful
        _success = abi.decode(_data, (bool));

        // Update Reputation
        _updateSolverReputation(_solverOps, uint128(_repMagnitude), _success);

        // Handle gas token balance reimbursement (reimbursement from Atlas and the congestion buy ins)
        _gasRefundTracker = _processCongestionRake(_gasRefundTracker, _userOpHash, _success);

        // Transfer the appropriate gas tokens
        if (_gasRefundTracker > 0) SafeTransferLib.safeTransferETH(msg.sender, _gasRefundTracker);
    }

    function _validateSwap(UserOperation calldata userOp) internal {
        if (msg.sender != userOp.from) revert FLOnlineOuter_ValidateSwap_InvalidSender();
        // TODO: Add back gas checks when we have more clarity
        // if (gas > gasleft()) {
        //     revert FLOnlineOuter_ValidateSwap_TxGasTooHigh();
        // }
        // if (gas < gasleft() - 30_000) {
        //     revert FLOnlineOuter_ValidateSwap_TxGasTooLow();
        // }
        if (userOp.gas <= MAX_SOLVER_GAS * 2) {
            revert FLOnlineOuter_ValidateSwap_GasLimitTooLow();
        }

        (SwapIntent memory _swapIntent, BaselineCall memory _baselineCall) =
            abi.decode(userOp.data[4:], (SwapIntent, BaselineCall));

        // Verify that if we're dealing with the native gas token that the balances add up
        if (_swapIntent.tokenUserSells == address(0)) {
            if (msg.value < userOp.value) revert FLOnlineOuter_ValidateSwap_MsgValueTooLow();
            if (userOp.value < _swapIntent.amountUserSells) revert FLOnlineOuter_ValidateSwap_UserOpValueTooLow();
            if (userOp.value != _baselineCall.value) revert FLOnlineOuter_ValidateSwap_UserOpBaselineValueMismatch();
        }
    }

    // TODO Fix when basic swap scenarios are passing
    function _metacallGasLimit(
        uint256 cumulativeGasReserved,
        uint256 totalGas,
        uint256 gasLeft
    )
        internal
        view
        returns (uint256 metacallGasLimit)
    {
        // Reduce any unnecessary gas to avoid Atlas's excessive gas bundler penalty
        cumulativeGasReserved += METACALL_GAS_BUFFER; // TODO maybe make this higher?

        // Sets metacallGasLimit to the minimum of {totalGas, gasLeft, cumulativeGasReserved}
        // metacallGasLimit = totalGas > gasLeft
        //     ? (gasLeft > cumulativeGasReserved ? cumulativeGasReserved : gasLeft)
        //     : (totalGas > cumulativeGasReserved ? cumulativeGasReserved : totalGas);

        // console.log("cumulativeGasReserved:", cumulativeGasReserved);
        // console.log("totalGas:", totalGas);
        // console.log("gasLeft:", gasLeft);
        // console.log("metacallGasLimit:", metacallGasLimit);

        // TODO remove this once fixed, hacky bypass for gas issues
        return gasLeft - 100_000;
    }

    fallback() external payable { }

    receive() external payable { }
}
