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
        address swapper,
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall
    )
        external
        payable
        returns (address, SwapIntent memory, BaselineCall memory)
    {
        require(msg.sender == ATLAS, "SwapIntentDAppControl: InvalidSender");
        require(address(this) != CONTROL, "SwapIntentDAppControl: MustBeDelegated");
        require(swapIntent.tokenUserSells != swapIntent.tokenUserBuys, "SwapIntentDAppControl: SellIsSurplus");

        // User = control = bundler
        require(_user() == CONTROL, "SwapIntentDAppControl: ControlNotOwner");
        require(_bundler() == CONTROL, "SwapIntentDAppControl: ControlNotBundler");
        require(IGeneralizedBackrunProxy(CONTROL).getUser() == swapper, "SwapIntentDAppControl: UserNotLocked");

        require(
            _availableFundsERC20(
                swapIntent.tokenUserSells, CONTROL, swapIntent.amountUserSells, ExecutionPhase.PreSolver
            ),
            "SwapIntentDAppControl: SellFundsUnavailable"
        );

        // Calculate the baseline swap amount from the frontend-sourced routing
        // This will typically be a uniswap v2 or v3 path.
        // NOTE: This runs inside a try/catch and is reverted.
        uint256 _baselineAmount = _getSwapBaseline(swapIntent, baselineCall);

        // Update the minAmountUserBuys with this value
        // NOTE: If all of the solvers fail to exceed this value, we'll redo this swap in the postOpsHook
        if (_baselineAmount >= swapIntent.minAmountUserBuys) {
            SwapIntent memory _swapIntent = swapIntent;
            BaselineCall memory _baselineCall = baselineCall;

            _swapIntent.minAmountUserBuys = _baselineAmount;
            _baselineCall.success = true;
            return (swapper, _swapIntent, _baselineCall);
        }
        return (swapper, swapIntent, baselineCall);
    }

    function _getSwapBaseline(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall
    )
        internal
        returns (uint256 baselineAmount)
    {
        (bool _success, bytes memory _data) =
            CONTROL.delegatecall(_forward(abi.encodeCall(this.baselineSwapWrapper, (swapIntent, baselineCall))));

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

    function baselineSwapWrapper(SwapIntent calldata swapIntent, BaselineCall calldata baselineCall) external {
        (address _activeEnvironment,, uint8 _phase) = IAtlas(ATLAS).lock();

        require(address(this) == _activeEnvironment, "BackupRouter: NotActiveEnvironment");
        require(_phase == _baselinePhase, "BackupRouter: IncorrectPhase");
        require(msg.sender == ATLAS, "BackupRouter: InvalidSender");

        (bool _success, bytes memory _data) =
            swapIntent.tokenUserBuys.staticcall(abi.encodeCall(IERC20.balanceOf, address(this)));
        require(_success, "BackupRouter: BalanceCheckFail1");

        // Track the balance (count any previously-forwarded tokens)
        uint256 _startingBalance = abi.decode(_data, (uint256));

        // Optimistically transfer to the solver contract the tokens that the user is selling
        _transferUserERC20(swapIntent.tokenUserSells, address(this), swapIntent.amountUserSells);

        // Approve the router (NOTE that this approval happens inside the try/catch)
        SafeTransferLib.safeApprove(swapIntent.tokenUserSells, baselineCall.to, swapIntent.amountUserSells);

        // Perform the Baseline Call
        (_success,) = baselineCall.to.call(baselineCall.data);
        require(_success, "BackupRouter: BaselineCallFail");

        // Track the balance delta
        (_success, _data) = swapIntent.tokenUserBuys.staticcall(abi.encodeCall(IERC20.balanceOf, address(this)));
        require(_success, "BackupRouter: BalanceCheckFail2");

        uint256 _endingBalance = abi.decode(_data, (uint256));
        require(_endingBalance > _startingBalance, "BackupRouter: NoBalanceIncrease");

        // Revert gracefully to undo the swap but show the baseline amountOut
        revert BaselineFailSuccessful(_endingBalance - _startingBalance);
    }
}