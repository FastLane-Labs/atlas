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
import { BaseStorage } from "src/contracts/examples/fastlane-online/BaseStorage.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
}

contract FastLaneOnlineInner is BaseStorage, FastLaneOnlineControl {
    error BaselineFailSuccessful(uint256 baselineAmount);
    error BaselineFailFailure();

    uint8 private constant _baselinePhase = uint8(ExecutionPhase.UserOperation);

    constructor(address _atlas) FastLaneOnlineControl(_atlas) { }

    /////////////////////////////////////////////////////////
    //        EXECUTION ENVIRONMENT FUNCTIONS              //
    //                                                     //
    /////////////////////////////////////////////////////////

    /*
    * @notice This is the user operation target function
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev selector = ??
    * @dev It checks that the user has approved Atlas to spend the tokens they are selling
    * @param swapIntent The SwapIntent struct
    * @return swapIntent The SwapIntent struct
    */
    function swap(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall
    )
        external
        payable
        returns (SwapIntent memory, BaselineCall memory)
    {
        require(msg.sender == ATLAS, "SwapIntentDAppControl: InvalidSender");
        require(address(this) != CONTROL, "SwapIntentDAppControl: MustBeDelegated");
        require(swapIntent.tokenUserSells != swapIntent.tokenUserBuys, "SwapIntentDAppControl: SellIsSurplus");

        // User = control = bundler
        require(_bundler() == CONTROL, "SwapIntentDAppControl: ControlNotBundler");

        // Transfer sell token if it isn't gastoken and validate value deposit if it is
        if (swapIntent.tokenUserSells != address(0)) {
            _transferUserERC20(swapIntent.tokenUserSells, address(this), swapIntent.amountUserSells);
        } else {
            // UserOp.value already passed to this contract - ensure that userOp.value matches sell amount
            require(msg.value >= swapIntent.amountUserSells, "SwapIntentDAppControl: NativeTokenValue1");
            require(baselineCall.value >= swapIntent.amountUserSells, "SwapIntentDAppControl: NativeTokenValue2");
        }

        // Calculate the baseline swap amount from the frontend-sourced routing
        // This will typically be a uniswap v2 or v3 path.
        // NOTE: This runs inside a try/catch and is reverted.
        uint256 _baselineAmount = _catchSwapBaseline(swapIntent, baselineCall);

        // Update the minAmountUserBuys with this value
        // NOTE: If all of the solvers fail to exceed this value, we'll redo this swap in the postOpsHook
        // and verify that the min amount is exceeded.
        if (_baselineAmount >= swapIntent.minAmountUserBuys) {
            SwapIntent memory _swapIntent = swapIntent;
            _swapIntent.minAmountUserBuys = _baselineAmount;
            return (_swapIntent, baselineCall);
        }
        return (swapIntent, baselineCall);
    }

    function _catchSwapBaseline(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall
    )
        internal
        returns (uint256 baselineAmount)
    {
        (bool _success, bytes memory _data) =
            CONTROL.delegatecall(_forward(abi.encodeCall(this.baselineSwapTryCatcher, (swapIntent, baselineCall))));

        if (_success) revert(); // unreachable

        if (bytes4(_data) == BaselineFailSuccessful.selector) {
            // Get the uint256 from the memory array
            assembly {
                let dataLocation := add(_data, 0x20)
                baselineAmount := mload(add(dataLocation, sub(mload(_data), 32)))
            }
            return baselineAmount;
        }
        return 0;
    }

    function baselineSwapTryCatcher(SwapIntent calldata swapIntent, BaselineCall calldata baselineCall) external {
        // Do the baseline swap and get the amount received
        uint256 _received = _baselineSwap(swapIntent, baselineCall);

        // Revert gracefully to undo the swap but show the baseline amountOut
        // NOTE: This does not check the baseline amount against the user's minimum requirement
        // This is to allow solvers a chance to succeed even if the baseline swap has returned
        // an unacceptable amount (such as if it were sandwiched to try and nullify the swap).
        revert BaselineFailSuccessful(_received);
    }
}
