//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import {IEscrow} from "../../interfaces/IEscrow.sol";

import "../../types/CallTypes.sol";

// Atlas DApp-Control Imports
import {DAppControl} from "../../dapp/DAppControl.sol";

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
    Condition[] conditions; // Optional. Address and calldata that the user can staticcall to verify arbitrary conditions on chain
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


contract SwapIntentController is DAppControl {
    using SafeTransferLib for ERC20;

    uint256 constant public USER_CONDITION_GAS_LIMIT = 20_000; 
    uint256 constant public MAX_USER_CONDITIONS = 5;
    // NOTE: Conditionals will only be static called to prevent the user from arbitrarily altering state prior to 
    // the execution of the Solvers' calls. 

    uint256 constant public EXPECTED_GAS_USAGE_EX_SOLVER = 200_000;

    constructor(address _escrow)
        DAppControl(
            _escrow, 
            msg.sender, 
            CallConfig({
                sequenced: false,
                requirePreOps: true,
                trackPreOpsReturnData: true,
                trackUserReturnData: false,
                localUser: true,
                delegateUser: true,
                preSolver: true,
                postSolver: true,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: true,
                userBundler: true,
                dAppBundler: true,
                unknownBundler: true
            })
        )
    {}

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    // swap() selector = 0x98434997
    function swap(bytes calldata data) public payable {
        require(msg.sender == escrow, "ERR-PI002 InvalidSender");
        require(_approvedCaller() == control, "ERR-PI003 InvalidLockState");
        require(address(this) != control, "ERR-PI004 MustBeDelegated");

        // NOTE: To avoid redundant memory buildup, we pass the user's calldata all the way through
        // to the swap function. Because of this, it will still have its function selector. 
        require(bytes4(data) == this.swap.selector, "ERR-PI005 NoDuplicateSelector");

        SwapIntent memory swapIntent =abi.decode(data[4:], (SwapIntent));

        require(ERC20(swapIntent.tokenUserSells).balanceOf(_user()) >= swapIntent.amountUserSells, "ERR-PI020 InsufficientUserBalance");
    }

    //////////////////////////////////
    //   ATLAS OVERRIDE FUNCTIONS   //
    //////////////////////////////////

    function _preOpsCall(UserCall calldata uCall)
        internal
        override
        returns (bytes memory)
    {
        require(bytes4(uCall.data) == this.swap.selector, "ERR-PI001 InvalidSelector");
        require(uCall.to == control, "ERR-PI006 InvalidUserTo");

        // This dApp control currently requires all 
        SwapIntent memory swapIntent = abi.decode(uCall.data[4:], (SwapIntent));

        // There should never be a balance on this ExecutionEnvironment greater than 1, but check
        // anyway so that the auction accounting isn't imbalanced by unexpected inventory. 

        require(swapIntent.tokenUserSells != swapIntent.auctionBaseCurrency, "ERR-PI008 SellIsSurplus");
        // TODO: If user is Selling Eth, convert it to WETH rather than rejecting. 

        // TODO: Could maintain a balance of "1" of each token to allow the user to save gas over multiple uses
        uint256 buyTokenBalance = ERC20(swapIntent.tokenUserBuys).balanceOf(address(this));
        if (buyTokenBalance > 0) { 
            ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), buyTokenBalance);
        }

        uint256 sellTokenBalance = ERC20(swapIntent.tokenUserSells).balanceOf(address(this));
        if (sellTokenBalance > 0) {
            ERC20(swapIntent.tokenUserSells).safeTransfer(_user(), sellTokenBalance);
        }

        if (swapIntent.auctionBaseCurrency != swapIntent.tokenUserSells || swapIntent.auctionBaseCurrency != swapIntent.tokenUserBuys) {
            if (swapIntent.auctionBaseCurrency == address(0)) {
                uint256 auctionBaseCurrencyBalance = address(this).balance;
                SafeTransferLib.safeTransferETH(_user(), auctionBaseCurrencyBalance);
            
            } else {
                uint256 auctionBaseCurrencyBalance = ERC20(swapIntent.auctionBaseCurrency).balanceOf(address(this));
                if (auctionBaseCurrencyBalance > 0) {
                    ERC20(swapIntent.tokenUserBuys).safeTransfer(_user(), auctionBaseCurrencyBalance);
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


        // If the user added any swap conditions, verify them here:
        if (swapIntent.conditions.length > 0) {
            // Track the excess gas that the user spends with their checks
            uint256 gasMarker = gasleft();

            require(swapIntent.conditions.length <= MAX_USER_CONDITIONS, "ERR-PI019 TooManyConditions");

            uint256 i;
            bool valid;
            uint256 maxUserConditions = swapIntent.conditions.length;
            bytes memory conditionData;

            for (; i < maxUserConditions; ) {
                (valid, conditionData) = swapIntent.conditions[i].antecedent.staticcall{gas: USER_CONDITION_GAS_LIMIT}(
                    swapIntent.conditions[i].context
                );
                require(valid && abi.decode(conditionData, (bool)), "ERR-PI021 ConditionUnsound");
                
                unchecked{ ++i; }
            }
            if (swapIntent.solverMustReimburseGas) {
                swapData.solverGasLiability += (gasMarker - gasleft());
            }
        }

        bytes memory preOpsReturnData = abi.encode(swapData);
        return preOpsReturnData;
    }

    function _userLocalDelegateCall(bytes calldata data) internal override returns (bytes memory nullData) {
        if (bytes4(data) == this.swap.selector) {
            swap(data);
        }
        return nullData;
    }

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
    function _allocateValueCall(bytes calldata data) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // NOTE: donateToBundler caps the donation at 110% of total gas cost.
        // Any remainder is then sent to the specified recipient. 
        // IEscrow(escrow).donateToBundler{value: address(this).balance}();
        (,,bytes memory returnData) = abi.decode(data, (uint256, BidData[], bytes));

        SwapData memory swapData = abi.decode(returnData, (SwapData));

        if (swapData.auctionBaseCurrency != address(0)) {
            uint256 auctionTokenBalance = ERC20(swapData.auctionBaseCurrency).balanceOf(address(this));
            ERC20(swapData.auctionBaseCurrency).safeTransfer(_user(), auctionTokenBalance);
        
        // If the solver was already required to reimburse the user's gas, don't reallocate
        // Ether surplus to the bundler
        } else if (swapData.solverGasLiability > 0) {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);

        // Donate the ether to the bundler, with the surplus going back to the user
        } else {
            IEscrow(escrow).donateToBundler{value: address(this).balance}(_user());
        }
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

    function getBidFormat(UserCall calldata uCall) external pure override returns (BidData[] memory) {
        // This is a helper function called by solvers
        // so that they can get the proper format for
        // submitting their bids to the hook.

        (SwapIntent memory swapIntent) = abi.decode(uCall.data[4:], (SwapIntent));
    
        BidData[] memory bidData = new BidData[](1);

        bidData[0] = BidData({
            token: swapIntent.auctionBaseCurrency, 
            bidAmount: 0 // <- solver must update
        });

        return bidData;
    }

    function getBidValue(SolverOperation calldata solverOp)
        external
        pure
        override
        returns (uint256) 
    {
        return solverOp.bids[0].bidAmount;
    }

    // NOTE: This helper function is still delegatecalled inside of the execution environment
    function _validateUserOperation(UserCall calldata uCall) internal view override returns (bool) {
        if (bytes4(uCall.data) != this.swap.selector) {
            return false;
        }

        SwapIntent memory swapIntent =abi.decode(uCall.data[4:], (SwapIntent));

        // Check that user has enough tokens
        if (ERC20(swapIntent.tokenUserSells).balanceOf(_user()) < swapIntent.amountUserSells) {
            return false;
        }

        // Check that the correct permit has been granted
        if (ERC20(swapIntent.tokenUserSells).allowance(_user(), escrow) < swapIntent.amountUserSells) {
            return false;
        }

        uint256 maxUserConditions = swapIntent.conditions.length;
        if (maxUserConditions > MAX_USER_CONDITIONS) {
            return false;
        }

        uint256 i;
        bool valid;
        bytes memory conditionData;

        for (; i < maxUserConditions; ) {
            (valid, conditionData) = swapIntent.conditions[i].antecedent.staticcall{gas: USER_CONDITION_GAS_LIMIT}(
                swapIntent.conditions[i].context
            );
            if (!valid) {
                return false;
            }
            valid = abi.decode(conditionData, (bool));
            if (!valid) {
                return false;
            }
            
            unchecked{ ++i; }
        }
        return true;
    }

    fallback() external payable {
        console.log("inside fallback in SwapIntent");
    }
    receive() external payable {
        console.log("inside receive in SwapIntent");
    }
}
