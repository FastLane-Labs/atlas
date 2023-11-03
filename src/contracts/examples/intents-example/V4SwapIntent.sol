//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import {IEscrow} from "../../interfaces/IEscrow.sol";

import {CallConfig} from "../../types/DAppApprovalTypes.sol";
import "../../types/UserCallTypes.sol";
import "../../types/SolverCallTypes.sol";
import "../../types/LockTypes.sol";

// Atlas DApp-Control Imports
import {DAppControl} from "../../dapp/DAppControl.sol";

import "forge-std/Test.sol";

// Those are the intents that the user inputs
struct ExactInputIntent {
    address tokenIn;
    address tokenOut;
    uint256 maxFee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint256 sqrtPriceLimitX96;
}

struct ExactOutputIntent {
    address tokenIn;
    address tokenOut;
    uint256 maxFee;
    address recipient;
    uint256 amountInMaximum;
    uint256 amountOut;
    uint256 sqrtPriceLimitX96;
}

// This struct is for passing around data internally
struct SwapData {
    address tokenIn;
    address tokenOut;
    int256 requestedAmount; // positive for exact in, negative for exact out
    uint256 limitAmount; // if exact in, min amount out. if exact out, max amount in
    address recipient;
    uint256 solverGasLiability; // the amount of user gas that the solver must refund
}

contract V4SwapIntentController is DAppControl {
    using SafeTransferLib for ERC20;

    uint256 public constant EXPECTED_GAS_USAGE_EX_SOLVER = 200_000;
    address constant V4_POOL = address(0);

    uint256 startingBalance; // Balance tracked for the v4 pool

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
                userBundler: true,
                solverBundler: true,
                verifySolverBundlerCallChainHash: true,
                unknownBundler: true,
                forwardReturnData: false
            })
        )
    {}

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    modifier verifyCall(address tokenIn, address tokenOut, uint256 amount) {
        require(msg.sender == escrow, "ERR-PI002 InvalidSender");
        require(_approvedCaller() == control, "ERR-PI003 InvalidLockState");
        require(address(this) != control, "ERR-PI004 MustBeDelegated");

        address user = _user();

        // TODO: Could maintain a balance of "1" of each token to allow the user to save gas over multiple uses
        uint256 tokenInBalance = ERC20(tokenIn).balanceOf(address(this));
        if (tokenInBalance > 0) {
            ERC20(tokenIn).safeTransfer(user, tokenInBalance);
        }

        uint256 tokenOutBalance = ERC20(tokenOut).balanceOf(address(this));
        if (tokenOutBalance > 0) {
            ERC20(tokenOut).safeTransfer(user, tokenOutBalance);
        }

        require(
            _availableFundsERC20(tokenIn, user, amount, ExecutionPhase.SolverOperations),
            "ERR-PI059 SellFundsUnavailable"
        );
        _;
    }

    function exactInputSingle(ExactInputIntent calldata exactInputIntent)
        external
        payable
        verifyCall(exactInputIntent.tokenIn, exactInputIntent.tokenOut, exactInputIntent.amountIn)
        returns (SwapData memory)
    {
        SwapData memory swapData = SwapData({
            tokenIn: exactInputIntent.tokenIn,
            tokenOut: exactInputIntent.tokenOut,
            requestedAmount: int256(exactInputIntent.amountIn),
            limitAmount: exactInputIntent.amountOutMinimum,
            recipient: exactInputIntent.recipient,
            solverGasLiability: EXPECTED_GAS_USAGE_EX_SOLVER
        });

        return swapData;
    }

    function exactOutputSingle(ExactOutputIntent calldata exactOutputIntent)
        external
        payable
        verifyCall(exactOutputIntent.tokenIn, exactOutputIntent.tokenOut, exactOutputIntent.amountInMaximum)
        returns (SwapData memory)
    {
        SwapData memory swapData = SwapData({
            tokenIn: exactOutputIntent.tokenIn,
            tokenOut: exactOutputIntent.tokenOut,
            requestedAmount: -int256(exactOutputIntent.amountOut),
            limitAmount: exactOutputIntent.amountInMaximum,
            recipient: exactOutputIntent.recipient,
            solverGasLiability: EXPECTED_GAS_USAGE_EX_SOLVER
        });

        return swapData;
    }

    //////////////////////////////////
    //   ATLAS OVERRIDE FUNCTIONS   //
    //////////////////////////////////

    function _preSolverCall(bytes calldata data) internal override returns (bool) {
        (address solverTo, uint256 solverBid, bytes memory returnData) = abi.decode(data, (address, uint256, bytes));
        if (solverTo == address(this) || solverTo == _control() || solverTo == escrow) {
            return false;
        }

        SwapData memory swapData = abi.decode(returnData, (SwapData));

        // Record balance and transfer to the solver
        if (swapData.requestedAmount > 0) {
            // exact input
            startingBalance = ERC20(swapData.tokenIn).balanceOf(V4_POOL);
            _transferUserERC20(swapData.tokenIn, solverTo, uint256(swapData.requestedAmount));
        } else {
            // exact output
            startingBalance = ERC20(swapData.tokenOut).balanceOf(V4_POOL);
            _transferUserERC20(swapData.tokenIn, solverTo, swapData.limitAmount - solverBid);
            // For exact output swaps, the solvers compete and bid on how much tokens they can
            // return to the user in excess of their specified limit input. We only transfer what they
            // require to make the swap in this step.
        }

        // TODO: Permit69 is currently enabled during solver phase, but there is low conviction that this
        // does not enable an attack vector. Consider enabling to save gas on a transfer?
        return true;
    }

    // Checking intent was fulfilled, and user has received their tokens, happens here
    function _postSolverCall(bytes calldata data) internal override returns (bool) {
        (address solverTo, uint256 solverBid, bytes memory returnData) = abi.decode(data, (address, uint256, bytes));

        SwapData memory swapData = abi.decode(returnData, (SwapData));

        if (swapData.solverGasLiability > 0) {
            // NOTE: Winning solver does not have to reimburse for other solvers
            uint256 expectedGasReimbursement = swapData.solverGasLiability * tx.gasprice;

            // Is this check unnecessary since it'll just throw inside the try/catch?
            // if (address(this).balance < expectedGasReimbursement) {
            //    return false;
            //}

            // NOTE: This sends any surplus donations back to the solver
            console.log("sending surplus donations back to solver...");
            IEscrow(escrow).donateToBundler{value: expectedGasReimbursement}(solverTo);
        }

        uint256 buyTokenBalance = ERC20(swapData.tokenOut).balanceOf(address(this));
        uint256 amountUserBuys =
            swapData.requestedAmount > 0 ? swapData.limitAmount : uint256(-swapData.requestedAmount);

        // If it was an exact input swap, we need to verify that
        // a) We have enough tokens to meet the user's minimum amount out
        // b) The output amount matches (or is greater than) the solver's bid
        if (swapData.requestedAmount > 0) {
            if (buyTokenBalance < swapData.limitAmount) {
                return false; // insufficient amount out
            }
            if (buyTokenBalance < solverBid) {
                return false; // does not meet solver bid
            }
        }

        // no need to check for exact output, since the max is whatever the user transferred

        if (buyTokenBalance < amountUserBuys) {
            return false;
        }

        // Make sure not to transfer any extra 'auctionBaseCurrency' token, since that will be used
        // for the auction measurements
        address auctionBaseCurrency = swapData.requestedAmount > 0 ? swapData.tokenOut : swapData.tokenIn;

        if (swapData.tokenOut != auctionBaseCurrency) {
            ERC20(swapData.tokenOut).safeTransfer(swapData.recipient, buyTokenBalance);
        } else {
            ERC20(swapData.tokenOut).safeTransfer(swapData.recipient, amountUserBuys);
        }
        return true;
    }

    // This occurs after a Solver has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // NOTE: donateToBundler caps the donation at 110% of total gas cost.
        // Any remainder is then sent to the specified recipient.
        // IEscrow(escrow).donateToBundler{value: address(this).balance}();
        SwapData memory swapData = abi.decode(data, (SwapData));

        if (bidToken != address(0)) {
            ERC20(bidToken).safeTransfer(_user(), bidAmount);

            // If the solver was already required to reimburse the user's gas, don't reallocate
            // Ether surplus to the bundler
        } else if (swapData.solverGasLiability > 0) {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);

            // Donate the ether to the bundler, with the surplus going back to the user
        } else {
            console.log("donating to bundler in SwapIntent");
            IEscrow(escrow).donateToBundler{value: address(this).balance}(_user());
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

        if (userOp.data[4:] == this.exactInputSingle.selector) {
            ExactInputIntent memory exactInputIntent = abi.decode(userOp.data[4:], (ExactInputIntent));
            bidToken = exactInputIntent.tokenOut;
        } else if (userOp.data[4:] == this.exactOutputSingle.selector) {
            ExactOutputIntent memory exactOutputIntent = abi.decode(userOp.data[4:], (ExactOutputIntent));
            bidToken = exactOutputIntent.tokenIn;
        } else {
            revert("InvalidFunctionSelector");
        }
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
