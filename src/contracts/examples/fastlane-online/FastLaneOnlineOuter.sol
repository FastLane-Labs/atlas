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

interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
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
        uint256 _gasTokenBalance = address(this).balance;

        // Transfer the user's sell tokens to here.
        SafeTransferLib.safeTransferFrom(
            swapIntent.tokenUserSells, msg.sender, address(this), swapIntent.amountUserSells
        );

        // Get any SolverOperations
        SolverOperation[] memory _solverOps = _getSolverOps(userOpHash);

        // Execute if we have price improvement potential from Solvers.
        bool _success = _solverOps.length > 0;
        if (_success) {
            // Approve Atlas for that amount.
            SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, swapIntent.amountUserSells);

            // Build DAppOp
            DAppOperation memory _dAppOp = _getDAppOp(userOpHash, deadline);

            // Encode and Metacall
            bytes memory _data = abi.encodeCall(IAtlas.metacall, (_userOp, _solverOps, _dAppOp));

            (_success, _data) = ATLAS.call(_data);
            // NOTE: Do not revert if the Atlas call failed.

            // Undo the token approval
            SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, 0);
        }

        // If metacall failed or if it was never executed, do the baseline call locally
        if (!_success) {
            _baselineSwap(swapIntent, baselineCall);
        }

        // Handle gas token balance reimbursement (reimbursement from Atlas and the congestion buy ins)
        _gasTokenBalance = address(this).balance - _gasTokenBalance + S_aggCongestionBuyIn[userOpHash];
        delete S_aggCongestionBuyIn[userOpHash];

        // Transfer the appropriate gas tokens and any leftover sell tokens to the User.
        // NOTE: The transfer of the Buy token is already handled inside either the Atlas call or the baseline call
        SafeTransferLib.safeTransfer(swapIntent.tokenUserSells, msg.sender, _getERC20Balance(swapIntent.tokenUserBuys));
        SafeTransferLib.safeTransferETH(msg.sender, _gasTokenBalance);
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
        // Track the balance (count any previously-forwarded tokens)
        uint256 _startingBalance = _getERC20Balance(swapIntent.tokenUserBuys);

        // Approve the baseline router (NOTE that this approval does NOT happen inside the try/catch)
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, baselineCall.to, swapIntent.amountUserSells);

        // Perform the Baseline Call
        (bool _success,) = baselineCall.to.call(baselineCall.data);
        require(_success, "Outer: BaselineCallFail");

        // Track the balance delta
        uint256 _endingBalance = _getERC20Balance(swapIntent.tokenUserBuys);

        // Verify swap amount exceeds slippage threshold
        require(_endingBalance - _startingBalance > swapIntent.minAmountUserBuys, "Outer: InsufficientAmount");

        // Reset the approval
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, baselineCall.to, 0);

        // Transfer the purchased tokens to the swapper.
        SafeTransferLib.safeTransfer(swapIntent.tokenUserBuys, msg.sender, _endingBalance);
    }
}
