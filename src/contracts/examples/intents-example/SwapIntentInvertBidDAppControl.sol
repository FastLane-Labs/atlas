//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import { IEscrow } from "../../interfaces/IEscrow.sol";

import { CallConfig } from "../../types/DAppApprovalTypes.sol";
import "../../types/UserCallTypes.sol";
import "../../types/SolverCallTypes.sol";
import "../../types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "../../dapp/DAppControl.sol";

import "forge-std/Test.sol";

/**
 * @notice SwapIntent where user wants exact amount of `tokenUserBuys` and is willing to sell up to `maxAmountUserSells`
 * of
 * `tokenUserSells` for it
 */
struct SwapIntent {
    address tokenUserBuys;
    address tokenUserSells;
    uint256 amountUserBuys;
    uint256 maxAmountUserSells;
}

/**
 * @title SwapIntentInvertBidDAppControl
 * @notice A DAppControl contract that allows a user to swap tokens with a solver using a `SwapIntent`
 * @dev The invertBidValue flag is set to true
 */
contract SwapIntentInvertBidDAppControl is DAppControl {
    using SafeTransferLib for ERC20;

    bool public immutable _solverBidRetrievalRequired;

    constructor(
        address _atlas,
        bool bidFind,
        bool solverBidRetrievalRequired
    )
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
                preSolver: true,
                postSolver: true,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: true,
                userAuctioneer: false,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: true,
                trustedOpHash: true,
                invertBidValue: true,
                exPostBids: bidFind
            })
        )
    {
        _solverBidRetrievalRequired = solverBidRetrievalRequired;
    }

    // ---------------------------------------------------- //
    //                       Custom                         //
    // ---------------------------------------------------- //

    /*
    * @notice This is the user operation target function
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It checks that the user has approved Atlas to spend the tokens they are selling and the conditions are met
    * @param swapIntent The SwapIntent struct
    */
    function swap(SwapIntent calldata swapIntent) external payable returns (SwapIntent memory) {
        require(msg.sender == ATLAS, "SwapIntentDAppControl: InvalidSender");
        require(_addressPointer() == CONTROL, "SwapIntentDAppControl: InvalidLockState");
        require(address(this) != CONTROL, "SwapIntentDAppControl: MustBeDelegated");

        address user = _user();

        require(
            _availableFundsERC20(
                swapIntent.tokenUserSells, user, swapIntent.maxAmountUserSells, ExecutionPhase.PreSolver
            ),
            "SwapIntentDAppControl: SellFundsUnavailable"
        );

        return SwapIntent({
            tokenUserBuys: swapIntent.tokenUserBuys,
            tokenUserSells: swapIntent.tokenUserSells,
            amountUserBuys: swapIntent.amountUserBuys,
            maxAmountUserSells: swapIntent.maxAmountUserSells
        });
    }

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
        address solverTo = solverOp.solver;
        if (solverTo == address(this) || solverTo == _control() || solverTo == ATLAS) {
            revert("Invalid solver address - solverOp.solver cannot be execution environment, dapp control or atlas");
        }

        SwapIntent memory swapData = abi.decode(returnData, (SwapIntent));

        // The solver must be bidding less than the intent's maxAmountUserSells
        require(solverOp.bidAmount <= swapData.maxAmountUserSells, "SwapIntentInvertBid: BidTooHigh");

        if (_solverBidRetrievalRequired) {
            // Optimistically transfer to the execution environment the amount that the solver is invert bidding
            _transferUserERC20(swapData.tokenUserSells, address(this), solverOp.bidAmount);
            // Approve the solver to retrieve the bid amount from ee
            ERC20(swapData.tokenUserSells).safeApprove(solverTo, solverOp.bidAmount);
        } else {
            // Optimistically transfer to the solver contract the amount that the solver is invert bidding
            _transferUserERC20(swapData.tokenUserSells, solverTo, solverOp.bidAmount);
        }
    }

    /*
    * @notice This function is called after a solver operation executed
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers to the user the tokens they are buying
    * @param _
    * @param returnData The return data from the user operation (swap data)
    * @return true if the transfer was successful, false otherwise
    */
    function _postSolverCall(SolverOperation calldata, bytes calldata returnData) internal override {
        SwapIntent memory swapIntent = abi.decode(returnData, (SwapIntent));
        uint256 buyTokenBalance = ERC20(swapIntent.tokenUserBuys).balanceOf(address(this));

        if (buyTokenBalance < swapIntent.amountUserBuys) {
            revert("SwapIntentInvertBid: Intent Unfulfilled - buyTokenBalance < amountUserBuys");
        }

        // Transfer the tokens the user is buying to the user
        ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), swapIntent.amountUserBuys);
    }

    /*
    * @notice This function is called after a solver has successfully paid their bid
    * @dev This function transfers any excess `tokenUserSells` tokens back to the user
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers all the available bid tokens on the contract (instead of only the bid amount,
    *      to avoid leaving any dust on the contract)
    * @param bidToken The address of the token used for the winning solver operation's bid
    * @param _
    * @param _
    */
    function _allocateValueCall(address bidToken, uint256, bytes calldata) internal override {
        if (bidToken != address(0)) {
            ERC20(bidToken).safeTransfer(_user(), ERC20(bidToken).balanceOf(address(this)));
        } else {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);
        }
    }

    // ---------------------------------------------------- //
    //                 Getters and helpers                  //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        (SwapIntent memory swapIntent) = abi.decode(userOp.data[4:], (SwapIntent));
        bidToken = swapIntent.tokenUserSells;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
