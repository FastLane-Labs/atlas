//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";
import { FastLaneOnlineErrors } from "src/contracts/examples/fastlane-online/FastLaneOnlineErrors.sol";

// NEVER EVER GIVE TOKEN APPROVALS TO THIS CONTRACT
contract BaselineSwapper is FastLaneOnlineErrors {
    address public immutable FASTLANE_ONLINE;

    constructor() {
        FASTLANE_ONLINE = msg.sender;
    }

    function baselineSwap(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        address swapper
    )
        external
    {
        if (msg.sender != FASTLANE_ONLINE) revert BaselineSwapper_InvalidEntry();

        // Track the balance (count any previously-forwarded tokens)
        uint256 _startingBalance = _getERC20Balance(swapIntent.tokenUserBuys);

        // Approve the baseline router (NOTE that this approval does NOT happen inside the try/catch)
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, baselineCall.to, swapIntent.amountUserSells);

        // Perform the Baseline Call
        (bool _success, bytes memory _data) = baselineCall.to.call(baselineCall.data);
        // Bubble up the error on failure
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        // Track the balance delta
        uint256 _endingBalance = _getERC20Balance(swapIntent.tokenUserBuys);

        // Verify swap amount exceeds slippage threshold
        if (_endingBalance - _startingBalance <= swapIntent.minAmountUserBuys) {
            revert BaselineSwapper_InsufficientAmount();
        }

        // Reset the approval
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, baselineCall.to, 0);

        // Transfer the purchased tokens to the swapper.
        SafeTransferLib.safeTransfer(swapIntent.tokenUserBuys, swapper, _endingBalance);

        // Send back any leftover sell tokens.
        _endingBalance = _getERC20Balance(swapIntent.tokenUserSells);
        if (_endingBalance > 0) {
            SafeTransferLib.safeTransfer(swapIntent.tokenUserSells, swapper, _endingBalance);
        }
    }

    function _getERC20Balance(address token) internal view returns (uint256 balance) {
        (bool _success, bytes memory _data) = token.staticcall(abi.encodeCall(IERC20.balanceOf, address(this)));
        if (!_success) revert BaselineSwapper_BalanceCheckFail();
        balance = abi.decode(_data, (uint256));
    }
}
