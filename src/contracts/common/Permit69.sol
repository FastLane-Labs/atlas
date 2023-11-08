//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {GasAccounting} from "../atlas/GasAccounting.sol";

import "../types/LockTypes.sol";
import "../types/EscrowTypes.sol";

import {EXECUTION_PHASE_OFFSET, SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER, SAFE_GAS_TRANSFER} from "../libraries/SafetyBits.sol";

// NOTE: IPermit69 only works inside of the Atlas environment - specifically
// inside of the custom ExecutionEnvironments that each user deploys when
// interacting with Atlas in a manner controlled by the DeFi dApp.


// The name comes from the reciprocal nature of the token transfers. Both
// the user and the DAppControl can transfer tokens from the User
// and the DAppControl contracts... but only if they each have granted
// token approval to the Atlas main contract, and only during specific phases
// of the Atlas execution process.

abstract contract Permit69 is GasAccounting {
    using SafeTransferLib for ERC20;

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _simulator
    ) GasAccounting(_escrowDuration, _factory, _verification, _gasAccLib, _simulator) {}

    // Virtual Functions defined by other Atlas modules
    function _verifyCallerIsExecutionEnv(
        address user,
        address controller,
        uint32 callConfig
    ) internal virtual {}

    // Transfer functions
    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address controller,
        uint32 callConfig,
        uint16 lockState
    ) external {
        // Verify that the caller is legitimate
        // NOTE: Use the *current* controller's codehash to help mitigate social engineering bamboozles if, for example, 
        // a DAO is having internal issues. 
        _verifyCallerIsExecutionEnv(user, controller, callConfig);

        // Verify the lock state
        _verifyLockState({
            lockState: lockState, 
            safeExecutionPhaseSet: SAFE_USER_TRANSFER
        });

        // Transfer token
        ERC20(token).safeTransferFrom(user, destination, amount);
    }

    function transferDAppERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address controller,
        uint32 callConfig,
        uint16 lockState
    ) external {
        // Verify that the caller is legitimate
        _verifyCallerIsExecutionEnv(user, controller, callConfig);

        // Verify the lock state
        _verifyLockState({
            lockState: lockState, 
            safeExecutionPhaseSet: SAFE_DAPP_TRANSFER
        });

        // Transfer token
        ERC20(token).safeTransferFrom(controller, destination, amount);
    }

    function requestGasFrom(Party donor, Party recipient, uint256 amt, uint16 lockState) external {
        // Verify the parties
        if(!_validParties(msg.sender, donor, recipient)) revert InvalidEnvironment();

        // Verify the lock state
        _verifyLockState({
            lockState: lockState, 
            safeExecutionPhaseSet: SAFE_GAS_TRANSFER
        });

        _requestFrom(donor, recipient, amt);
    }

    function contributeGasTo(Party donor, Party recipient, uint256 amt, uint16 lockState) external {
        // Verify the parties
        if(!_validParties(msg.sender, donor, recipient)) revert InvalidEnvironment();

        // Verify the lock state
        _verifyLockState({
            lockState: lockState, 
            safeExecutionPhaseSet: SAFE_GAS_TRANSFER
        });

        _contributeTo(donor, recipient, amt);
    }

    function _verifyLockState(uint16 lockState, uint16 safeExecutionPhaseSet) internal pure {
        if(lockState & safeExecutionPhaseSet == 0){
            revert InvalidLockState();
        }
        // TODO: Do we need the below require? 
        // Intuition is that we'd need to block all reentry into EE to bypass this check 
        // require(msg.sender == activeEnvironment, "ERR-T003 EnvironmentNotActive");
    }
}
