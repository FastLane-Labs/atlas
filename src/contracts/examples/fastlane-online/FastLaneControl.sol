//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

contract FastLaneOnlineControl is DAppControl {
    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: true,
                requirePreSolver: true,
                requirePostSolver: false,
                requirePostOps: true,
                zeroSolvers: true,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: false,
                forwardReturnData: true,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: true,
                allowAllocateValueFailure: false
            })
        )
    { }

    // ---------------------------------------------------- //
    //                     Atlas hooks                      //
    // ---------------------------------------------------- //

    /*
    * @notice This function is called before a solver operation executes
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers the tokens that the user is selling to the solver
    * @param solverOp The SolverOperation that is about to execute
    * @return true if the transfer was successful, false otherwise
    */
    function _preSolverCall(SolverOperation calldata solverOp, bytes calldata returnData) internal override {
        (, SwapIntent memory _swapIntent,) = abi.decode(returnData, (address, SwapIntent, BaselineCall));

        // Make sure the token is correct
        require(solverOp.bidToken == _swapIntent.tokenUserBuys, "FLOnlineControl: BuyTokenMismatch");
        require(solverOp.bidToken != _swapIntent.tokenUserSells, "FLOnlineControl: SellTokenMismatch");

        // NOTE: This module is unlike the generalized swap intent module - here, the solverOp.bidAmount includes
        // the min amount that the user expects.
        require(solverOp.bidAmount >= _swapIntent.minAmountUserBuys, "FLOnlineControl: BidBelowReserve");

        // Optimistically transfer to the solver contract the tokens that the user is selling
        _transferUserERC20(_swapIntent.tokenUserSells, solverOp.solver, _swapIntent.amountUserSells);

        return; // success
    }

    /*
    * @notice This function is called after a solver has successfully paid their bid
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers all the available bid tokens on the contract (instead of only the bid amount,
    *      to avoid leaving any dust on the contract)
    * @param bidToken The address of the token used for the winning solver operation's bid
    * @param _
    * @param _
    */
    function _allocateValueCall(address, uint256, bytes calldata returnData) internal override {
        (address _swapper, SwapIntent memory _swapIntent,) = abi.decode(returnData, (address, SwapIntent, BaselineCall));

        uint256 _buyTokenBalance = IERC20(_swapIntent.tokenUserBuys).balanceOf(address(this));

        SafeTransferLib.safeTransfer(_swapIntent.tokenUserBuys, _swapper, _buyTokenBalance);
    }

    /*
    * @notice This function is called before a solver operation executes
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers the tokens that the user is selling to the solver
    * @param solverOp The SolverOperation that is about to execute
    * @return true if the transfer was successful, false otherwise
    */
    function _postOpsCall(bool solved, bytes calldata returnData) internal override {
        // Return early if a Solver already beat the reserve price
        if (solved) return;

        (address _swapper, SwapIntent memory _swapIntent, BaselineCall memory _baselineCall) =
            abi.decode(returnData, (address, SwapIntent, BaselineCall));

        // Revert early if the baseline call reverted or did not meet the min bid (no reason to run it twice on the same
        // state)
        if (!_baselineCall.success) revert();

        // Track the balance (count any previously-forwarded tokens)
        (bool _success, bytes memory _data) =
            _swapIntent.tokenUserBuys.staticcall(abi.encodeCall(IERC20.balanceOf, address(this)));
        require(_success, "FLOnlineControlPost: BalanceCheckFail1");
        uint256 _startingBalance = abi.decode(_data, (uint256));

        // Optimistically transfer to the solver contract the tokens that the user is selling
        _transferUserERC20(_swapIntent.tokenUserSells, address(this), _swapIntent.amountUserSells);

        // Approve the router (NOTE that this approval happens inside the try/catch)
        SafeTransferLib.safeApprove(_swapIntent.tokenUserSells, _baselineCall.to, _swapIntent.amountUserSells);

        // Perform the Baseline Call
        (_success,) = _baselineCall.to.call(_baselineCall.data);
        require(_success, "FLOnlineControlPost: BaselineCallFail");

        // Track the balance delta
        (_success, _data) = _swapIntent.tokenUserBuys.staticcall(abi.encodeCall(IERC20.balanceOf, address(this)));
        require(_success, "FLOnlineControlPost: BalanceCheckFail2");
        uint256 _endingBalance = abi.decode(_data, (uint256));

        // Make sure the min amount out was hit
        require(
            _endingBalance >= _startingBalance + _swapIntent.minAmountUserBuys, "FLOnlineControlPost: ReserveNotMet"
        );

        // Remove router approval
        SafeTransferLib.safeApprove(_swapIntent.tokenUserSells, _baselineCall.to, 0);

        // Transfer the tokens back to the original user
        SafeTransferLib.safeTransfer(_swapIntent.tokenUserBuys, _swapper, _endingBalance);

        return; // success
    }

    // ---------------------------------------------------- //
    //                 Getters and helpers                  //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        (, SwapIntent memory _swapIntent,) = abi.decode(userOp.data[4:], (address, SwapIntent, BaselineCall));
        bidToken = _swapIntent.tokenUserBuys;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
