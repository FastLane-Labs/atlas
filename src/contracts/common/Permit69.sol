//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { GasAccounting } from "src/contracts/atlas/GasAccounting.sol";

import { SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "src/contracts/libraries/SafetyBits.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/EscrowTypes.sol";

// NOTE: IPermit69 only works inside of the Atlas environment - specifically
// inside of the custom ExecutionEnvironments that each user deploys when
// interacting with Atlas in a manner controlled by the DeFi dApp.

// The name comes from the reciprocal nature of the token transfers. Both
// the user and the DAppControl can transfer tokens from the User
// and the DAppControl contracts... but only if they each have granted
// token approval to the Atlas main contract, and only during specific phases
// of the Atlas execution process.

/// @title Permit69
/// @author FastLane Labs
/// @notice Permit69 manages ERC20 approvals and transfers between Atlas and Execution Environment contracts during
/// metacall transactions.
abstract contract Permit69 is GasAccounting {
    using SafeTransferLib for ERC20;

    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        GasAccounting(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    /// @notice Verifies that the caller is an authorized Execution Environment contract.
    /// @dev This function is called internally to ensure that the caller is a legitimate Execution Environment contract
    /// controlled by the current DAppControl contract. It helps prevent unauthorized access and ensures that
    /// token transfers are performed within the context of Atlas's controlled environment. The implementation of this
    /// function can be found in Atlas.sol
    /// @param user The address of the user invoking the function.
    /// @param control The address of the current DAppControl contract.
    /// @param callConfig The CallConfig of the DAppControl contract of the current transaction.
    function _verifyCallerIsExecutionEnv(address user, address control, uint32 callConfig) internal virtual { }

    /// @notice Transfers ERC20 tokens from a user to a destination address, only callable by the expected Execution
    /// Environment.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    /// @param user The address of the user invoking the function.
    /// @param control The address of the current DAppControl contract.
    /// @param callConfig The CallConfig of the current DAppControl contract.
    /// @param lockState The lock state indicating the safe execution phase for the token transfer.
    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control,
        uint32 callConfig,
        uint16 lockState
    )
        external
    {
        // Verify that the caller is legitimate
        // NOTE: Use the *current* DAppControl's codehash to help mitigate social engineering bamboozles if, for
        // example, a DAO is having internal issues.
        _verifyCallerIsExecutionEnv(user, control, callConfig);

        // Verify the lock state
        _verifyLockState({ lockState: lockState, safeExecutionPhaseSet: SAFE_USER_TRANSFER });

        // Transfer token
        ERC20(token).safeTransferFrom(user, destination, amount);
    }

    /// @notice Transfers ERC20 tokens from the DAppControl contract to a destination address, only callable by the
    /// expected Execution Environment.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    /// @param user The address of the user invoking the function.
    /// @param control The address of the current DAppControl contract.
    /// @param callConfig The CallConfig of the current DAppControl contract.
    /// @param lockState The lock state indicating the safe execution phase for the token transfer.
    function transferDAppERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control,
        uint32 callConfig,
        uint16 lockState
    )
        external
    {
        // Verify that the caller is legitimate
        _verifyCallerIsExecutionEnv(user, control, callConfig);

        // Verify the lock state
        _verifyLockState({ lockState: lockState, safeExecutionPhaseSet: SAFE_DAPP_TRANSFER });

        // Transfer token
        ERC20(token).safeTransferFrom(control, destination, amount);
    }

    /// @notice Verifies whether the lock state allows execution in the specified safe execution phase.
    /// @param lockState The lock state to be checked.
    /// @param safeExecutionPhaseSet The set of safe execution phases.
    function _verifyLockState(uint16 lockState, uint16 safeExecutionPhaseSet) internal pure {
        if (lockState & safeExecutionPhaseSet == 0) {
            revert InvalidLockState();
        }
    }
}
