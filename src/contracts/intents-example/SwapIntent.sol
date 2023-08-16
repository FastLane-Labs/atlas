//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";

import {SafetyBits} from "../libraries/SafetyBits.sol";

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

// Atlas Protocol-Control Imports
import {ProtocolControl} from "../protocol/ProtocolControl.sol";

import "forge-std/Test.sol";

struct SwapIntent {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address surplusToken; // NOTE: Typically will be address(0) / ETH for gas refund
    // NOTE: surplusToken is the base currency of the auction
}


contract SwapIntentController is ProtocolControl {
    using SafeTransferLib for ERC20;

    constructor(address _escrow)
        ProtocolControl(
            _escrow, 
            msg.sender, 
            false, 
            true, 
            true, 
            true, 
            true,
            true, 
            false, 
            false, 
            true, 
            true,
            true,
            true)
    {}

    /*
    constructor(
        address escrowAddress,
        address governanceAddress,
        bool _sequenced, -> false
        bool _requireStaging, -> true
        bool _localUser, -> true
        bool _delegateUser, -> true
        bool _searcherStaging, -> true
        bool _searcherFulfillment, -> true
        bool _requireVerification, -> false
        bool _zeroSearchers, -> false
        bool _reuseUserOp, -> true
        bool _userBundler, -> true
        bool _protocolBundler, -> true
        bool _unknownBundler -> true
    )
    */

    // swap() selector = 0x98434997
    function swap(SwapIntent calldata swapIntent) external payable {
        console.log("swap called");
        console.log("msg.sender", msg.sender);
        console.log("escrow", escrow);

        require(msg.sender == escrow, "ERR-PI002 InvalidSender");
        require(ISafetyLocks(escrow).approvedCaller() == control, "ERR-PI003 InvalidLockState");
        require(address(this) != control, "ERR-PI004 MustBeDelegated");

        console.log("got here in swap in SwapIntent");


        uint256 sellTokenBalance = ERC20(swapIntent.tokenUserSells).balanceOf(address(this));

        // Transfer the tokens that the user is selling into the ExecutionEnvironment
        if (sellTokenBalance > swapIntent.amountUserSells) {
            ERC20(swapIntent.tokenUserSells).safeTransfer(_user(), sellTokenBalance - swapIntent.amountUserSells);
        
        } else if (sellTokenBalance > 0) {
            _transferUserERC20(swapIntent.tokenUserSells, address(this), swapIntent.amountUserSells - sellTokenBalance);
        
        } else { 
            _transferUserERC20(swapIntent.tokenUserSells, address(this), swapIntent.amountUserSells);
        }
    }

    function _stagingCall(address to, address, bytes4 userSelector, bytes calldata userData)
        internal
        override
        returns (bytes memory)
    {
        require(userSelector == this.swap.selector, "ERR-PI001 InvalidSelector");
        require(to == control, "ERR-PI006 InvalidUserTo");

        // This protocol control currently requires all 
        SwapIntent memory swapIntent = abi.decode(userData, (SwapIntent));

        // There should never be a balance on this ExecutionEnvironment, but check
        // so that the auction accounting isn't imbalanced by unexpected inventory. 

        require(swapIntent.tokenUserSells != swapIntent.surplusToken, "ERR-PI008 SellIsSurplus");
        // TODO: If user is Selling Eth, convert it to WETH rather than rejecting. 

        uint256 buyTokenBalance = ERC20(swapIntent.tokenUserBuys).balanceOf(address(this));
        if (buyTokenBalance > 0) {
            ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), buyTokenBalance);
        }
        
        if (swapIntent.surplusToken != swapIntent.tokenUserSells || swapIntent.surplusToken != swapIntent.tokenUserBuys) {
            if (swapIntent.surplusToken == address(0)) {
                uint256 surplusTokenBalance = address(this).balance;
                SafeTransferLib.safeTransferETH(_user(), surplusTokenBalance);
            
            } else {
                uint256 surplusTokenBalance = ERC20(swapIntent.surplusToken).balanceOf(address(this));
                if (surplusTokenBalance > 0) {
                    ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), surplusTokenBalance);
                }
            }
        }

        return userData;
    }

    function _searcherStagingCall(bytes calldata data) internal override returns (bool) {
        (bytes memory stagingReturnData, address searcherTo) = abi.decode(data, (bytes, address));
        SwapIntent memory swapIntent = abi.decode(stagingReturnData, (SwapIntent));

        // Optimistically transfer the searcher contract the tokens that the user is selling
        ERC20(swapIntent.tokenUserSells).safeTransfer(searcherTo, swapIntent.amountUserSells);
        
        // TODO: Permit69 is currently disabled during searcher phase, but there is currently
        // no understood attack vector possible. Consider enabling to save gas on a transfer?
        //_transferUserERC20(swapIntent.tokenUserSells, searcherTo, swapIntent.amountUserSells);
        return true;
    }

    function _fulfillmentCall(bytes calldata data) internal override returns (bool) {
        (bytes memory stagingReturnData,) = abi.decode(data, (bytes, address));
        SwapIntent memory swapIntent = abi.decode(stagingReturnData, (SwapIntent));

        uint256 buyTokenBalance = ERC20(swapIntent.tokenUserBuys).balanceOf(address(this));
        
        if (buyTokenBalance >= swapIntent.amountUserBuys) {

            // Make sure not to transfer any extra surplus token, since that will be used
            // for the auction measurements
            if (swapIntent.tokenUserBuys != swapIntent.surplusToken) {
                ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), buyTokenBalance);
            } else {
                ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), swapIntent.amountUserBuys);
            }
            return true;
        
        } else {
            return false;
        }
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingCall(bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // NOTE: donateToBundler caps the donation at 110% of total gas cost.
        // Any remainder is then sent to the user. 
        IEscrow(escrow).donateToBundler{value: address(this).balance}();
    }

    function _verificationCall(bytes calldata data) internal override returns (bool) {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow
    }

    /////////////////////////////////////////////////////////
    ///////////////// GETTERS & HELPERS // //////////////////
    /////////////////////////////////////////////////////////
    // NOTE: These are not delegatecalled
    function getPayeeData(bytes calldata) external view override returns (PayeeData[] memory) {
        // This function is called by the backend to get the
        // payee data, and by the Atlas Factory to generate a
        // hash to verify the backend.

        bytes memory data; // empty bytes

        PaymentData[] memory payments = new PaymentData[](1);

        payments[0] = PaymentData({payee: control, payeePercent: 100});

        PayeeData[] memory payeeData = new PayeeData[](1);

        payeeData[0] = PayeeData({token: address(0), payments: payments, data: data});
        return payeeData;
    }

    function getBidFormat(bytes calldata) external pure override returns (BidData[] memory) {
        // This is a helper function called by searchers
        // so that they can get the proper format for
        // submitting their bids to the hook.

        BidData[] memory bidData = new BidData[](1);

        bidData[0] = BidData({
            token: address(0), // <-- ETH
            bidAmount: 0 // <- searcher must update
        });

        return bidData;
    }
}
