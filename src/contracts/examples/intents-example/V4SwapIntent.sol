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

// This is the SwapIntent that the user inputs
struct SwapIntent {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address auctionBaseCurrency; // NOTE: Typically will be address(0) / ETH for gas refund
    bool solverMustReimburseGas; // If true, the solver must reimburse the bundler for the user's and control's gas cost
}

// This struct is for passing around data internally
struct SwapData {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address auctionBaseCurrency; // NOTE: Typically will be address(0) / ETH for gas refund
    uint256 solverGasLiability; // the amount of user gas that the solver must refund
}


contract V4SwapIntentController is DAppControl {
    using SafeTransferLib for ERC20;

    uint256 constant public EXPECTED_GAS_USAGE_EX_SOLVER = 200_000;

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
            _availableFundsERC20(swapIntent.tokenUserSells, user, swapIntent.amountUserSells, ExecutionPhase.SolverOperations),
            "ERR-PI059 SellFundsUnavailable"
        );

        if (swapIntent.auctionBaseCurrency != swapIntent.tokenUserSells || swapIntent.auctionBaseCurrency != swapIntent.tokenUserBuys) {
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
            auctionBaseCurrency: swapIntent.auctionBaseCurrency,
            solverGasLiability: swapIntent.solverMustReimburseGas ? EXPECTED_GAS_USAGE_EX_SOLVER : 0
        });

        return swapData;
    }

    //////////////////////////////////
    //   ATLAS OVERRIDE FUNCTIONS   //
    //////////////////////////////////

    function _preSolverCall(bytes calldata data) internal override returns (bool) {
        (address solverTo, bytes memory returnData) = abi.decode(data, (address, bytes));
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
       
        (address solverTo, bytes memory returnData) = abi.decode(data, (address, bytes));

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

        (SwapIntent memory swapIntent) = abi.decode(userOp.data[4:], (SwapIntent));

        bidToken = swapIntent.auctionBaseCurrency;
    }

    function getBidValue(SolverOperation calldata solverOp)
        public
        pure
        override
        returns (uint256) 
    {
        return solverOp.bidAmount;
    }
}
