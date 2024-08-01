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

import { BaselineSwapper } from "src/contracts/examples/fastlane-online/BaselineSwapper.sol";
import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { FastLaneOnlineInner } from "src/contracts/examples/fastlane-online/FastLaneOnlineInner.sol";
import { SolverGateway } from "src/contracts/examples/fastlane-online/SolverGateway.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
}

interface IBaselineSwapper {
    function baselineSwap(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        address swapper
    )
        external;
}

contract FastLaneOnlineOuter is SolverGateway {
    constructor(address _atlas) SolverGateway(_atlas) { }

    //////////////////////////////////////////////
    // THIS IS WHAT THE USER INTERACTS THROUGH.
    //////////////////////////////////////////////
    function fastOnlineSwap(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas,
        bytes32 userOpHash
    )
        external
        withUserLock
        onlyAsControl
    {
        // Get the UserOperation
        UserOperation memory _userOp =
            _getUserOperation(msg.sender, swapIntent, baselineCall, deadline, gas, maxFeePerGas);

        // Validate the parameters
        require(
            userOpHash == IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(_userOp),
            "ERR - USER HASH MISMATCH"
        );
        _validateSwap(swapIntent, deadline, gas, maxFeePerGas);

        // Track the gas token balance to repay the swapper with
        uint256 _gasRefundTracker = address(this).balance;

        // Now that we have the standardized userOpHash we can update the userOp's gas limit
        _userOp.gas = METACALL_GAS_BUFFER;

        // Transfer the user's sell tokens to here and then approve Atlas for that amount.
        SafeTransferLib.safeTransferFrom(
            swapIntent.tokenUserSells, msg.sender, address(this), swapIntent.amountUserSells
        );
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, swapIntent.amountUserSells);

        // Get any SolverOperations
        (SolverOperation[] memory _solverOps, uint256 _cumulativeGasReserved) = _getSolverOps(userOpHash);

        // Execute if we have price improvement potential from Solvers.
        bool _success = _solverOps.length > 0;
        if (_success) {
            // Transfer the user's sell tokens to here for Atlas to use
            SafeTransferLib.safeTransferFrom(
                swapIntent.tokenUserSells, msg.sender, address(this), swapIntent.amountUserSells
            );

            // Approve Atlas for that amount (Permit69)
            SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, swapIntent.amountUserSells);

            // Build DAppOp
            DAppOperation memory _dAppOp = _getDAppOp(userOpHash, deadline);

            // Encode and Metacall
            // NOTE: Do not revert if the Atlas call failed.

            (_success,) = ATLAS.call{ gas: _metacallGasLimit(_cumulativeGasReserved, gas, gasleft()) }(
                abi.encodeCall(IAtlas.metacall, (_userOp, _solverOps, _dAppOp))
            );

            // Undo the token approval
            SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, 0);

            // If metacall was successful, transfer any leftover sell tokens to the User.
            // NOTE: The transfer of the bought token is already handled inside either the Atlas call or the baseline
            // call
            uint256 _sellTokenBalance = _getERC20Balance(swapIntent.tokenUserSells);
            if (_success) {
                if (_sellTokenBalance > 0) {
                    SafeTransferLib.safeTransfer(swapIntent.tokenUserSells, msg.sender, _sellTokenBalance);
                }

                // If metacall wasn't successful, transfer the sell tokens to the BaselineSwapper
            } else {
                SafeTransferLib.safeTransfer(swapIntent.tokenUserSells, BASELINE_SWAPPER, _sellTokenBalance);
            }

            // If there were no solvers, bypass the metacall
        } else {
            // Transfer tokens straight from the swapper to the BaselineSwapper contract
            SafeTransferLib.safeTransferFrom(
                swapIntent.tokenUserSells, msg.sender, BASELINE_SWAPPER, swapIntent.amountUserSells
            );
        }

        // If metacall failed or if it was never executed, do the baseline call from the Baseline contract
        if (!_success) {
            bytes memory _data = abi.encodeCall(IBaselineSwapper.baselineSwap, (swapIntent, baselineCall, msg.sender));
            (_success, _data) = BASELINE_SWAPPER.call(_data);
            // Bubble up error on fail
            if (!_success) {
                assembly {
                    revert(add(_data, 32), mload(_data))
                }
            }
        }

        // Handle gas token balance reimbursement (reimbursement from Atlas and the congestion buy ins)
        // NOTE: We do not pay the congestion fees to the user
        _gasRefundTracker = _processCongestionRake(address(this).balance - _gasRefundTracker, userOpHash);

        // Transfer the appropriate gas tokens
        SafeTransferLib.safeTransferETH(msg.sender, _gasRefundTracker);
    }

    function _validateSwap(
        SwapIntent calldata swapIntent,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas
    )
        internal
    {
        require(deadline >= block.number, "ERR - DEADLINE PASSED");
        require(maxFeePerGas >= tx.gasprice, "ERR - INVALID GASPRICE");
        require(gas > gasleft(), "ERR - TX GAS TOO HIGH");
        require(gas < gasleft() - 30_000, "ERR - TX GAS TOO LOW");
        require(gas > MAX_SOLVER_GAS * 2, "ERR - GAS LIMIT TOO LOW");
        require(swapIntent.tokenUserSells != address(0), "ERR - CANT SELL ZERO ADDRESS");
        require(swapIntent.tokenUserBuys != address(0), "ERR - CANT BUY ZERO ADDRESS");

        // Increment the user's local nonce
        unchecked {
            ++S_userNonces[msg.sender];
        }
    }

    function _baselineSwap(SwapIntent calldata swapIntent, BaselineCall calldata baselineCall) internal {
        (bool _success, bytes memory _data) =
            BASELINE_SWAPPER.call(abi.encodeCall(IBaselineSwapper.baselineSwap, (swapIntent, baselineCall, msg.sender)));
        // Bubble up error on fail
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }
    }

    function _metacallGasLimit(
        uint256 cumulativeGasReserved,
        uint256 totalGas,
        uint256 gasLeft
    )
        internal
        pure
        returns (uint256 metacallGasLimit)
    {
        // Reduce any unnecessary gas to avoid Atlas's excessive gas bundler penalty
        cumulativeGasReserved += METACALL_GAS_BUFFER;
        metacallGasLimit = totalGas > gasLeft
            ? (gasLeft > cumulativeGasReserved ? cumulativeGasReserved : gasLeft)
            : (totalGas > cumulativeGasReserved ? cumulativeGasReserved : totalGas);
    }
}
