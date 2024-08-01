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
        payable
        withUserLock
        onlyAsControl
    {
        // Get the UserOperation
        UserOperation memory _userOp =
            _getUserOperation(msg.sender, swapIntent, baselineCall, deadline, gas, maxFeePerGas);

        // Validate the parameters
        if (userOpHash != IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(_userOp)) {
            revert FLOnlineOuter_FastOnlineSwap_UserOpHashMismatch();
        }
        _validateSwap(swapIntent, deadline, gas, maxFeePerGas);

        // Transfer the user's sell tokens to here and then approve Atlas for that amount.
        SafeTransferLib.safeTransferFrom(
            swapIntent.tokenUserSells, msg.sender, address(this), swapIntent.amountUserSells
        );
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, swapIntent.amountUserSells);

        // Get any SolverOperations
        SolverOperation[] memory _solverOps = _getSolverOps(userOpHash);

        // Build DAppOp
        DAppOperation memory _dAppOp = _getDAppOp(userOpHash, deadline);

        // Track the gas token balance to repay the swapper with, excluding the msg.value sent.
        uint256 _gasTokenBalance = address(this).balance - msg.value;

        // Metacall
        (bool _success, bytes memory _data) =
            ATLAS.call{ value: msg.value }(abi.encodeCall(IAtlas.metacall, (_userOp, _solverOps, _dAppOp)));
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        // Revert the token approval
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, ATLAS, 0);

        // Handle gas token balance reimbursement (reimbursement from Atlas and the congestion buy ins)
        _gasTokenBalance = address(this).balance - _gasTokenBalance + S_aggCongestionBuyIn[userOpHash];
        delete S_aggCongestionBuyIn[userOpHash];
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
        if (deadline < block.number) {
            revert FLOnlineOuter_ValidateSwap_DeadlinePassed();
        }
        if (maxFeePerGas < tx.gasprice) {
            revert FLOnlineOuter_ValidateSwap_InvalidGasPrice();
        }

        // TODO: Add back gas checks when we have more clarity
        // if (gas > gasleft()) {
        //     revert FLOnlineOuter_ValidateSwap_TxGasTooHigh();
        // }
        // if (gas < gasleft() - 30_000) {
        //     revert FLOnlineOuter_ValidateSwap_TxGasTooLow();
        // }

        if (gas <= MAX_SOLVER_GAS * 2) {
            revert FLOnlineOuter_ValidateSwap_GasLimitTooLow();
        }
        if (swapIntent.tokenUserSells == address(0)) {
            revert FLOnlineOuter_ValidateSwap_SellTokenZeroAddress();
        }
        if (swapIntent.tokenUserBuys == address(0)) {
            revert FLOnlineOuter_ValidateSwap_BuyTokenZeroAddress();
        }

        // Increment the user's local nonce
        unchecked {
            ++S_userNonces[msg.sender];
        }
    }

    fallback() external payable { }

    receive() external payable { }
}
