//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ISolverContract } from "../interfaces/ISolverContract.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import { ExecutionPhase } from "../types/LockTypes.sol";
import { Party } from "../types/EscrowTypes.sol";

import { Base } from "../common/ExecutionBase.sol";

import { CallBits } from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

import { FastLaneErrorsEvents } from "../types/Emissions.sol";

contract ExecutionEnvironment is Base {
    using CallBits for uint32;

    uint8 private constant _ENVIRONMENT_DEPTH = 1 << 1;

    constructor(address _atlas) Base(_atlas) { }

    modifier validUser(UserOperation calldata userOp) {
        if (userOp.from != _user()) {
            revert("ERR-CE02 InvalidUser");
        }
        if (userOp.to != atlas || userOp.dapp == atlas) {
            revert("ERR-EV007 InvalidTo");
        }
        _;
    }

    modifier validControlHash() {
        if (_control().codehash != _controlCodeHash()) {
            revert("ERR-EV008 InvalidCodeHash");
        }
        _;
    }


    modifier validSolver(SolverOperation calldata solverOp) {
        {
            address solverTo = solverOp.solver;
            address solverFrom = solverOp.from;
            address control = _control();

            if (solverTo == address(this) || solverTo == control || solverTo == atlas) {
                revert("ERR-EV008 InvalidTo");
            }
            if (solverTo != _approvedCaller()) {
                revert("ERR-EV009 WrongSolver");
            }
            if (solverFrom == _user() || solverFrom == solverTo || solverFrom == control) {
                revert("ERR-EV009 InvalidFrom");
            }
        }
        _;
    }

    //////////////////////////////////
    ///    CORE CALL FUNCTIONS     ///
    //////////////////////////////////
    function preOpsWrapper(UserOperation calldata userOp)
        external
        validUser(userOp)
        onlyAtlasEnvironment(ExecutionPhase.PreOps, _ENVIRONMENT_DEPTH)
        returns (bytes memory)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        bytes memory preOpsData = abi.encodeWithSelector(IDAppControl.preOpsCall.selector, userOp);

        bool success;
        (success, preOpsData) = _control().delegatecall(forward(preOpsData));

        require(success, "ERR-EC02 DelegateRevert");

        preOpsData = abi.decode(preOpsData, (bytes));
        return preOpsData;
    }

    function userWrapper(UserOperation calldata userOp)
        external
        payable
        validUser(userOp)
        onlyAtlasEnvironment(ExecutionPhase.UserOperation, _ENVIRONMENT_DEPTH)
        validControlHash
        returns (bytes memory userData)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        uint32 config = _config();

        require(address(this).balance >= userOp.value, "ERR-CE01 ValueExceedsBalance");

        bool success;

        if (config.needsDelegateUser()) {
            (success, userData) = userOp.dapp.delegatecall(forward(userOp.data));
            require(success, "ERR-EC02 DelegateRevert");

            // userData = abi.decode(userData, (bytes));
        } else {
            // regular user call - executed at regular destination and not performed locally
            (success, userData) = userOp.dapp.call{ value: userOp.value }(forward(userOp.data));
            require(success, "ERR-EC04a CallRevert");
        }
    }

    function postOpsWrapper(bytes calldata returnData)
        external
        onlyAtlasEnvironment(ExecutionPhase.PostOps, _ENVIRONMENT_DEPTH)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        bytes memory data = abi.encodeWithSelector(IDAppControl.postOpsCall.selector, returnData);

        bool success;
        (success, data) = _control().delegatecall(forward(data));

        require(success, "ERR-EC02 DelegateRevert");
        require(abi.decode(data, (bool)), "ERR-EC03a DelegateUnsuccessful");
    }

    function solverMetaTryCatch(
        uint256 gasLimit,
        SolverOperation calldata solverOp,
        bytes calldata dAppReturnData
    )
        external
        payable
        onlyAtlasEnvironment(ExecutionPhase.SolverOperations, _ENVIRONMENT_DEPTH)
    // No donate surplus here - donate after value xfer
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        // TODO: Change check to msg.value ?
        require(address(this).balance == solverOp.value, "ERR-CE05 IncorrectValue");

        console.log("solverOp.value in solverMetaTryCatch", solverOp.value);

        // Track token balance to measure if the bid amount is paid.
        bool etherIsBidToken;
        uint256 bidBalance;
        // Ether balance
        if (solverOp.bidToken == address(0)) {
            bidBalance = address(this).balance - solverOp.value; // NOTE: this is the meta tx value
            etherIsBidToken = true;
            // ERC20 balance
        } else {
            bidBalance = ERC20(solverOp.bidToken).balanceOf(address(this));
        }

        ////////////////////////////
        // SOLVER SAFETY CHECKS //
        ////////////////////////////

        // Verify that the DAppControl contract matches the solver's expectations
        if (solverOp.control != _control()) {
            revert FastLaneErrorsEvents.AlteredControlHash();
        }

        bool success;

        // Handle any solver preOps, if necessary
        if (_config().needsPreSolver()) {
            bytes memory data = abi.encode(solverOp.solver, dAppReturnData);

            data = abi.encodeWithSelector(IDAppControl.preSolverCall.selector, data);

            (success, data) = _control().delegatecall(forwardSpecial(data, ExecutionPhase.PreSolver));

            if (!success) {
                revert FastLaneErrorsEvents.PreSolverFailed();
            }

            success = abi.decode(data, (bool));
            if (!success) {
                revert FastLaneErrorsEvents.PreSolverFailed();
            }
        }

        // Execute the solver call.
        (success,) = ISolverContract(solverOp.solver).atlasSolverCall{ gas: gasLimit, value: solverOp.value }(
            solverOp.from,
            solverOp.bidToken,
            solverOp.bidAmount,
            solverOp.data,
            _config().forwardReturnData() ? dAppReturnData : new bytes(0)
        );

        // Verify that it was successful
        if (!success) {
            revert FastLaneErrorsEvents.SolverOperationReverted();
        }

        // If this was a user intent, handle and verify fulfillment
        if (_config().needsSolverPostCall()) {
            bytes memory data = dAppReturnData;

            data = abi.encode(solverOp.solver, data);

            data = abi.encodeWithSelector(IDAppControl.postSolverCall.selector, data);

            (success, data) = _control().delegatecall(forwardSpecial(data, ExecutionPhase.PostSolver));

            if (!success) {
                revert FastLaneErrorsEvents.PostSolverFailed();
            }

            success = abi.decode(data, (bool));
            if (!success) {
                revert FastLaneErrorsEvents.IntentUnfulfilled();
            }
        }

        // Verify that the solver paid what they bid
        uint256 balance = etherIsBidToken ? address(this).balance : ERC20(solverOp.bidToken).balanceOf(address(this));

        if (balance < bidBalance + solverOp.bidAmount) {
            revert FastLaneErrorsEvents.SolverBidUnpaid();
        }

        // Verify that the solver repaid their msg.value
        if (!IEscrow(atlas).validateBalances()) {
            revert FastLaneErrorsEvents.SolverMsgValueUnpaid();
        }
    }

    function allocateValue(
        address bidToken,
        uint256 bidAmount,
        bytes memory allocateData
    )
        external
        onlyAtlasEnvironment(ExecutionPhase.HandlingPayments, _ENVIRONMENT_DEPTH)
    {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment

        allocateData = abi.encodeWithSelector(IDAppControl.allocateValueCall.selector, bidToken, bidAmount, allocateData);

        (bool success,) = _control().delegatecall(forward(allocateData));
        require(success, "ERR-EC02 DelegateRevert");
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

    function getConfig() external pure returns (uint32 config) {
        config = _config();
    }

    function getEscrow() external view returns (address escrow) {
        escrow = atlas;
    }

    receive() external payable { }

    fallback() external payable { }
}
