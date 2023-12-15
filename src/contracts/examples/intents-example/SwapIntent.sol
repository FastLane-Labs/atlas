//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

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

struct Condition {
    address antecedent;
    bytes context;
}

// This is the SwapIntent that the user inputs
struct SwapIntent {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address auctionBaseCurrency; // NOTE: Typically will be address(0) / ETH for gas refund
    bool solverMustReimburseGas; // If true, the solver must reimburse the bundler for the user's and control's gas cost
    Condition[] conditions; // Optional. Address and calldata that the user can staticcall to verify arbitrary
        // conditions on chain
}

// This struct is for passing around data internally
struct SwapData {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address auctionBaseCurrency; // NOTE: Typically will be address(0) / ETH for gas refund
}

contract SwapIntentController is DAppControl {
    using SafeTransferLib for ERC20;

    uint256 public constant USER_CONDITION_GAS_LIMIT = 20_000;
    uint256 public constant MAX_USER_CONDITIONS = 5;
    // NOTE: Conditionals will only be static called to prevent the user from arbitrarily altering state prior to
    // the execution of the Solvers' calls.

    uint256 public constant EXPECTED_GAS_USAGE_EX_SOLVER = 200_000;

    constructor(address _escrow)
        DAppControl(
            _escrow,
            msg.sender,
            CallConfig({
                sequenced: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                localUser: false,
                delegateUser: true,
                preSolver: true,
                postSolver: true,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: true,
                userAuctioneer: true,
                solverAuctioneer: true,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: true
            })
        )
    { }

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    // swap() selector = 0x98434997
    function swap(SwapIntent calldata swapIntent) external payable returns (SwapData memory) {
        require(msg.sender == escrow, "ERR-PI002 InvalidSender");
        require(_approvedCaller() == control, "ERR-PI003 InvalidLockState");
        require(address(this) != control, "ERR-PI004 MustBeDelegated");

        address user = _user();

        // There should never be a balance on this ExecutionEnvironment greater than 1, but check
        // anyway so that the auction accounting isn't imbalanced by unexpected inventory.

        require(swapIntent.tokenUserSells != swapIntent.auctionBaseCurrency, "ERR-PI008 SellIsSurplus");
        // TODO: If user is Selling Eth, convert it to WETH rather than rejecting.

        // TODO: Could maintain a balance of "1" of each token to allow the user to save gas over multiple uses
        uint256 buyTokenBalance = ERC20(swapIntent.tokenUserBuys).balanceOf(address(this));
        if (buyTokenBalance > 0) {
            ERC20(swapIntent.tokenUserBuys).safeTransfer(user, buyTokenBalance);
        }

        uint256 sellTokenBalance = ERC20(swapIntent.tokenUserSells).balanceOf(address(this));
        if (sellTokenBalance > 0) {
            ERC20(swapIntent.tokenUserSells).safeTransfer(user, sellTokenBalance);
        }

        require(
            _availableFundsERC20(swapIntent.tokenUserSells, user, swapIntent.amountUserSells, ExecutionPhase.PreSolver),
            "ERR-PI059 SellFundsUnavailable"
        );

        if (
            swapIntent.auctionBaseCurrency != swapIntent.tokenUserSells
                || swapIntent.auctionBaseCurrency != swapIntent.tokenUserBuys
        ) {
            if (swapIntent.auctionBaseCurrency == address(0)) {
                uint256 auctionBaseCurrencyBalance = address(this).balance;
                SafeTransferLib.safeTransferETH(user, auctionBaseCurrencyBalance);
            } else {
                uint256 auctionBaseCurrencyBalance = ERC20(swapIntent.auctionBaseCurrency).balanceOf(address(this));
                if (auctionBaseCurrencyBalance > 0) {
                    ERC20(swapIntent.tokenUserBuys).safeTransfer(user, auctionBaseCurrencyBalance);
                }
            }
        }

        // Make a SwapData memory struct so that we don't have to pass around the full intent anymore
        SwapData memory swapData = SwapData({
            tokenUserBuys: swapIntent.tokenUserBuys,
            amountUserBuys: swapIntent.amountUserBuys,
            tokenUserSells: swapIntent.tokenUserSells,
            amountUserSells: swapIntent.amountUserSells,
            auctionBaseCurrency: swapIntent.auctionBaseCurrency
        });

        // If the user added any swap conditions, verify them here:
        if (swapIntent.conditions.length > 0) {
            // Track the excess gas that the user spends with their checks
            require(swapIntent.conditions.length <= MAX_USER_CONDITIONS, "ERR-PI019 TooManyConditions");

            uint256 i;
            bool valid;
            uint256 maxUserConditions = swapIntent.conditions.length;
            bytes memory conditionData;

            for (; i < maxUserConditions;) {
                (valid, conditionData) = swapIntent.conditions[i].antecedent.staticcall{ gas: USER_CONDITION_GAS_LIMIT }(
                    swapIntent.conditions[i].context
                );
                require(valid && abi.decode(conditionData, (bool)), "ERR-PI021 ConditionUnsound");

                unchecked {
                    ++i;
                }
            }
        }

        return swapData;
    }

    //////////////////////////////////
    //   ATLAS OVERRIDE FUNCTIONS   //
    //////////////////////////////////

    function _preSolverCall(bytes calldata data) internal override returns (bool) {
        (address solverTo,, bytes memory returnData) = abi.decode(data, (address, uint256, bytes));
        if (solverTo == address(this) || solverTo == _control() || solverTo == escrow) {
            return false;
        }

        SwapData memory swapData = abi.decode(returnData, (SwapData));

        // Optimistically transfer the solver contract the tokens that the user is selling
        _transferUserERC20(swapData.tokenUserSells, solverTo, swapData.amountUserSells);

        // TODO: Permit69 is currently enabled during solver phase, but there is low conviction that this
        // does not enable an attack vector. Consider enabling to save gas on a transfer?
        return true;
    }

    // Checking intent was fulfilled, and user has received their tokens, happens here
    function _postSolverCall(bytes calldata data) internal override returns (bool) {
        (,, bytes memory returnData) = abi.decode(data, (address, uint256, bytes));

        SwapData memory swapData = abi.decode(returnData, (SwapData));

        uint256 buyTokenBalance = ERC20(swapData.tokenUserBuys).balanceOf(address(this));

        if (buyTokenBalance >= swapData.amountUserBuys) {
            // Make sure not to transfer any extra 'auctionBaseCurrency' token, since that will be used
            // for the auction measurements
            if (swapData.tokenUserBuys != swapData.auctionBaseCurrency) {
                ERC20(swapData.tokenUserBuys).safeTransfer(_user(), buyTokenBalance);
            } else {
                ERC20(swapData.tokenUserBuys).safeTransfer(_user(), swapData.amountUserBuys);
            }
            return true;
        } else {
            return false;
        }
    }

    // This occurs after a Solver has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow
        if (bidToken != address(0)) {
            ERC20(bidToken).safeTransfer(_user(), bidAmount);
        } else {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);
        }
    }

    /////////////////////////////////////////////////////////
    ///////////////// GETTERS & HELPERS // //////////////////
    /////////////////////////////////////////////////////////
    // NOTE: These are not delegatecalled

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        // This is a helper function called by solvers
        // so that they can get the proper format for
        // submitting their bids to the hook.

        (SwapIntent memory swapIntent) = abi.decode(userOp.data[4:], (SwapIntent));

        bidToken = swapIntent.auctionBaseCurrency;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
