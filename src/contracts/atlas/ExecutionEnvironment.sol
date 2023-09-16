//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ISolverContract} from "../interfaces/ISolverContract.sol";
import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {IDAppControl} from "../interfaces/IDAppControl.sol";

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {UserCall, DAppConfig, SolverOperation, SolverCall, BidData} from "../types/CallTypes.sol";
import {ExecutionPhase} from "../types/LockTypes.sol";

import {Base} from "../common/ExecutionBase.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

import {
    FastLaneErrorsEvents
} from "../types/Emissions.sol";

contract ExecutionEnvironment is Base {
    using CallBits for uint16;
    
    constructor(address _atlas) Base(_atlas) {}

    modifier validUser(UserCall calldata uCall) {
        if (uCall.from != _user()) {
            revert("ERR-CE02 InvalidUser");
        }
        if (uCall.to == address(this) || uCall.to == atlas) {
            revert("ERR-EV007 InvalidTo");
        }
        _;
    }

    modifier validSolver(SolverCall calldata fCall) {
        {
        address solverTo = fCall.to;
        if (solverTo == address(this) || solverTo == _control() || solverTo == atlas) {
            revert("ERR-EV008 InvalidTo");
        }
        if (solverTo != _approvedCaller()) {
            revert("ERR-EV009 WrongSolver");
        }
        }
        _;
    }


    //////////////////////////////////
    ///    CORE CALL FUNCTIONS     ///
    //////////////////////////////////
    function preOpsWrapper(UserCall calldata uCall)
        external
        onlyAtlasEnvironment
        validUser(uCall)
        validPhase(ExecutionPhase.PreOps)
        returns (bytes memory)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        require(uCall.to != address(this), "ERR-EV008 InvalidTo");

        bytes memory preOpsData = abi.encodeWithSelector(
            IDAppControl.preOpsCall.selector, uCall
        );

        bool success;
        (success, preOpsData) = _control().delegatecall(
            forward(preOpsData)
        );

        require(success, "ERR-EC02 DelegateRevert");

        preOpsData = abi.decode(preOpsData, (bytes));
        return preOpsData;
    }

    function userWrapper(UserCall calldata uCall) 
        external 
        payable
        onlyAtlasEnvironment
        validUser(uCall)
        onlyActiveEnvironment
        validPhase(ExecutionPhase.UserOperation)
        returns (bytes memory userData) 
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        uint16 config = _config();

        require(address(this).balance >= uCall.value, "ERR-CE01 ValueExceedsBalance");

        bool success;

        if (!config.needsLocalUser()) {
            // regular user call - executed at regular destination and not performed locally
            (success, userData) = uCall.to.call{value: uCall.value}(
                forward(uCall.data)
            );
            require(success, "ERR-EC04a CallRevert");

        } else if (config.needsDelegateUser()) {
            userData = abi.encodeWithSelector(
                IDAppControl.userLocalCall.selector, uCall.data
            );

            (success, userData) = _control().delegatecall(forward(userData));

            require(success, "ERR-EC02 DelegateRevert");
        } else {
            revert("ERR-P02 UserOperationStatic");
        }
        userData = abi.decode(userData, (bytes));
    }

    function postOpsWrapper(bytes calldata returnData) 
        external 
        onlyAtlasEnvironment
        validPhase(ExecutionPhase.PostOps)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        bytes memory data = abi.encodeWithSelector(
            IDAppControl.postOpsCall.selector, returnData);
        
        bool success;
        (success, data) = _control().delegatecall(forward(data));

        require(success, "ERR-EC02 DelegateRevert");
        require(abi.decode(data, (bool)), "ERR-EC03a DelegateUnsuccessful");
    }

    function solverMetaTryCatch(
        uint256 gasLimit, 
        uint256 escrowBalance, 
        SolverOperation calldata solverOp, 
        bytes calldata returnData
    ) 
        external payable 
        onlyAtlasEnvironment 
        validSolver(solverOp.call)
        validPhase(ExecutionPhase.SolverOperations)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(address(this).balance == solverOp.call.value, "ERR-CE05 IncorrectValue");

        // Track token balances to measure if the bid amount is paid.
        uint256[] memory tokenBalances = new uint[](solverOp.bids.length);
        uint256 i;
        for (; i < solverOp.bids.length;) {
            // Ether balance
            if (solverOp.bids[i].token == address(0)) {
                tokenBalances[i] = msg.value; // NOTE: this is the meta tx value

            // ERC20 balance
            } else {
                tokenBalances[i] = ERC20(solverOp.bids[i].token).balanceOf(address(this));
            }
            unchecked {
                ++i;
            }
        }

        ////////////////////////////
        // SEARCHER SAFETY CHECKS //
        ////////////////////////////

        // Verify that the DAppControl contract matches the solver's expectations
        if(solverOp.call.controlCodeHash != _controlCodeHash()) {
            revert FastLaneErrorsEvents.AlteredControlHash();
        }

        bool success;

        // Handle any solver preOps, if necessary
        if (_config().needsPreSolver()) {

            bytes memory data = abi.encode(solverOp.call.to, returnData);

            data = abi.encodeWithSelector(
                IDAppControl.preSolverCall.selector, 
                data
            );

            (success, data) = _control().delegatecall(
                forward(data)
            );
            if(!success) {
                revert FastLaneErrorsEvents.PreSolverFailed();
            } 

            success = abi.decode(data, (bool));
            if(!success) {
                revert FastLaneErrorsEvents.PreSolverFailed();
            } 
        }

        // Execute the solver call.
        (success,) = ISolverContract(solverOp.call.to).atlasSolverCall{
            gas: gasLimit,
            value: solverOp.call.value
        }(solverOp.call.from, solverOp.bids, solverOp.call.data);

        // Verify that it was successful
        if(!success) {
            revert FastLaneErrorsEvents.SolverOperationReverted();
        } 

        // If this was a user intent, handle and verify fulfillment
        if (_config().needsSolverPostCall()) {
            
            bytes memory data = returnData;

            data = abi.encode(solverOp.call.to, data);

            data = abi.encodeWithSelector(
                IDAppControl.postSolverCall.selector, 
                // solverOp.call.to, 
                data
            );

            (success, data) = _control().delegatecall(
                forward(data)
            );
            if(!success) {
                revert FastLaneErrorsEvents.PostSolverFailed();
            } 

            success = abi.decode(data, (bool));
            if(!success) {
                revert FastLaneErrorsEvents.IntentUnfulfilled();
            }
        }


        // Verify that the solver paid what they bid
        bool etherIsBidToken;
        i = 0;
        uint256 balance;

        for (; i < solverOp.bids.length;) {
            // ERC20 tokens as bid currency
            if (!(solverOp.bids[i].token == address(0))) {
                balance = ERC20(solverOp.bids[i].token).balanceOf(address(this));
                if (balance < tokenBalances[i] + solverOp.bids[i].bidAmount) {
                    revert FastLaneErrorsEvents.SolverBidUnpaid();
                }

                // Native Gas (Ether) as bid currency
            } else {
                balance = address(this).balance;
                if (balance < solverOp.bids[i].bidAmount) { // tokenBalances[i] = 0 for ether
                    revert FastLaneErrorsEvents.SolverBidUnpaid();
                }
        
                etherIsBidToken = true;

                // Transfer any surplus Ether back to escrow to add to solver's balance
                if (balance > solverOp.bids[i].bidAmount) {
                    SafeTransferLib.safeTransferETH(atlas, balance - solverOp.bids[i].bidAmount);
                }
            }
            unchecked {
                ++i;
            }
        }

        if (!etherIsBidToken) {
            uint256 currentBalance = address(this).balance;
            if (currentBalance > 0) {
                SafeTransferLib.safeTransferETH(atlas, currentBalance);
            }
        }

        // Verify that the solver repaid their msg.value
        // TODO: Add in a more discerning func that'll silo the 
        // donations to prevent double counting. 
        if (atlas.balance < escrowBalance) {
            revert FastLaneErrorsEvents.SolverMsgValueUnpaid();
        }
    }

    function allocateRewards(BidData[] calldata bids, bytes memory returnData) 
        external 
        onlyAtlasEnvironment
        validPhase(ExecutionPhase.HandlingPayments)
    {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment

        uint256 totalEtherReward;
        uint256 payment;
        uint256 i;

        BidData[] memory netBids = new BidData[](bids.length);

        for (; i < bids.length;) {
            payment = (bids[i].bidAmount * 5) / 100;

            if (bids[i].token != address(0)) {
                SafeTransferLib.safeTransfer(ERC20(bids[i].token), address(0xa71a5), payment);
                totalEtherReward = bids[i].bidAmount - payment; // NOTE: This is transferred to controller as msg.value
            } else {
                SafeTransferLib.safeTransferETH(address(0xa71a5), payment);
            }

            unchecked {
                netBids[i].token = bids[i].token;
                netBids[i].bidAmount = bids[i].bidAmount - payment;
                ++i;
            }
        }

        bytes memory allocateData = abi.encodeWithSelector(IDAppControl.allocatingCall.selector, abi.encode(totalEtherReward, bids, returnData));

        (bool success,) = _control().delegatecall(forward(allocateData));
        require(success, "ERR-EC02 DelegateRevert");
    }

    ///////////////////////////////////////
    //   HELPER / SEQUENCING FUNCTIONS   //
    ///////////////////////////////////////

    function validateUserOperation(UserCall calldata uCall)   
        external 
        // view 
        // onlyAtlas
        returns (bool) {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        if (uCall.from != _user()) {
            return false;
        }

        if (uCall.control != _control()) {
            return false;
        }

        if (uCall.deadline < block.number) {
            return false;
        }

        if (_controlCodeHash() != _control().codehash) {
            return false;
        }

        bytes memory data = abi.encodeWithSelector(
            IDAppControl.validateUserOperation.selector, uCall);

        (bool success, bytes memory returnData) = _control().delegatecall(forward(data));

        if (!success) {
            return false;
        }
        return abi.decode(returnData, (bool));
    }

    ///////////////////////////////////////
    //  USER SUPPORT / ACCESS FUNCTIONS  //
    ///////////////////////////////////////
    function withdrawERC20(address token, uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(ERC20(token), msg.sender, amount);
        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function factoryWithdrawERC20(address msgSender, address token, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(ERC20(token), _user(), amount);
        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function withdrawEther(uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function factoryWithdrawEther(address msgSender, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(_user(), amount);
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function getUser() external pure returns (address user) {
        user = _user();
    }

    function getControl() external pure returns (address control) {
        control = _control();
    }

    function getConfig() external pure returns (uint16 config) {
        config = _config();
    }

    function getEscrow() external view returns (address escrow) {
        escrow = atlas;
    }

    receive() external payable {}

    fallback() external payable {}
}
