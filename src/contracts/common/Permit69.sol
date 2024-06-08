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

    // TODO read lockState from Atlas transient storage var rather than allowing caller to pass in value

    /// @notice Verifies that the caller is an Execution Environment deployed using Atlas, given specific salt inputs.
    /// @dev Used by Execution Environments to ensure that only the original user can withdraw ETH or tokens from that
    /// particular Execution Environment.
    /// @dev The implementation of this function can be found in Atlas.sol
    /// @param user The original `UserOperation.from` address when the Execution Environment was created
    /// @param control The address of the DAppControl contract associated with the Execution Environment
    /// @param callConfig The CallConfig of the DAppControl associated with the Execution Environment. NOTE: Must match
    /// the CallConfig settings as they were when the Execution Environment was created.
    /// @return bool Indicating whether the caller is the correct Execution Environment (true) or not (false).
    function verifyCallerIsExecutionEnv(
        address user,
        address control,
        uint32 callConfig
    )
        external
        virtual
        returns (bool);

    /// @notice Transfers ERC20 tokens from the `currentUserFrom` address set at the start of the current metacall tx,
    /// to a destination address, only callable by the expected Execution Environment.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    /// @param lockState The lock state indicating the safe execution phase for the token transfer.
    function transferUserERC20(address token, address destination, uint256 amount, uint16 lockState) external {
        // Only the expected, currently active Execution Environment can call this function.
        _verifyCallerIsActiveExecutionEnv();

        // Verify the lock state
        _verifyLockState({ lockState: lockState, safeExecutionPhaseSet: SAFE_USER_TRANSFER });

        // Transfer token
        ERC20(token).safeTransferFrom(activeUser, destination, amount);
    }

    /// @notice Transfers ERC20 tokens from the `activeControl` address set at the start of the current metacall tx, to
    /// a destination address, only callable by the expected Execution Environment.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    /// @param lockState The lock state indicating the safe execution phase for the token transfer.
    function transferDAppERC20(address token, address destination, uint256 amount, uint16 lockState) external {
        // Only the expected, currently active Execution Environment can call this function.
        _verifyCallerIsActiveExecutionEnv();

        // Verify the lock state
        _verifyLockState({ lockState: lockState, safeExecutionPhaseSet: SAFE_DAPP_TRANSFER });

        // Transfer token
        ERC20(token).safeTransferFrom(activeControl, destination, amount);
    }

    /// @notice Verifies whether the lock state allows execution in the specified safe execution phase.
    /// @param lockState The lock state to be checked.
    /// @param safeExecutionPhaseSet The set of safe execution phases.
    function _verifyLockState(uint16 lockState, uint16 safeExecutionPhaseSet) internal pure {
        if (lockState & safeExecutionPhaseSet == 0) {
            revert InvalidLockState();
        }
    }

    /// @notice Verifies that the caller is the currently active Execution Environment.
    /// @dev Because user, control, and callConfig are used in the salt when creating the Execution Environment,
    /// we know that the user and DAppControl addresses associated with the calling EE are the same as the `userOp.from`
    /// and `userOp.control` addresses passed in the beginning of the current `metacall()` tx.
    function _verifyCallerIsActiveExecutionEnv() internal view {
        if (msg.sender != lock) {
            revert NotActiveExecutionEnv();
        }
    }
}
