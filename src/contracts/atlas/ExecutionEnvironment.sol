//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { ISolverContract } from "../interfaces/ISolverContract.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import { ExecutionPhase } from "../types/LockTypes.sol";

import { Base } from "../common/ExecutionBase.sol";

import { CallBits } from "../libraries/CallBits.sol";

import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "forge-std/Test.sol";

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

    modifier contributeSurplus() {
        _;
        {
            uint256 balance = address(this).balance;
            if (balance > 0) {
                IEscrow(atlas).contribute{ value: balance }();
            }
        }
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

        bytes memory preOpsData = forward(abi.encodeWithSelector(IDAppControl.preOpsCall.selector, userOp));

        bool success;
        (success, preOpsData) = _control().delegatecall(preOpsData);

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
        contributeSurplus
        returns (bytes memory returnData)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        uint32 config = _config();

        require(address(this).balance >= userOp.value, "ERR-CE01 ValueExceedsBalance");

        bool success;

        if (config.needsDelegateUser()) {
            (success, returnData) = userOp.dapp.delegatecall(forward(userOp.data));
            require(success, "ERR-EC02 DelegateRevert");
        } else {
            // regular user call - executed at regular destination and not performed locally
            (success, returnData) = userOp.dapp.call{ value: userOp.value }(forward(userOp.data));
            require(success, "ERR-EC04a CallRevert");
        }
    }

    function postOpsWrapper(
        bool solved,
        bytes calldata returnData
    )
        external
        onlyAtlasEnvironment(ExecutionPhase.PostOps, _ENVIRONMENT_DEPTH)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        bytes memory data = forward(abi.encodeWithSelector(IDAppControl.postOpsCall.selector, solved, returnData));

        bool success;
        (success, data) = _control().delegatecall(data);

        require(success, "ERR-EC02 DelegateRevert");
        require(abi.decode(data, (bool)), "ERR-EC03a DelegateUnsuccessful");
    }

    function solverMetaTryCatch(
        uint256 bidAmount,
        uint256 gasLimit,
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        onlyAtlasEnvironment(ExecutionPhase.SolverOperations, _ENVIRONMENT_DEPTH)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(address(this).balance == solverOp.value, "ERR-CE05 IncorrectValue");

        uint32 config = _config();
        address control = _control();

        // Track token balance to measure if the bid amount is paid.
        bool etherIsBidToken;
        uint256 startBalance;

        if (solverOp.bidToken == address(0)) {
            startBalance = 0; // address(this).balance - solverOp.value;
            etherIsBidToken = true;
            // ERC20 balance
        } else {
            startBalance = ERC20(solverOp.bidToken).balanceOf(address(this));
        }

        ////////////////////////////
        // SOLVER SAFETY CHECKS //
        ////////////////////////////

        // Verify that the DAppControl contract matches the solver's expectations
        if (solverOp.control != control) {
            revert AtlasErrors.AlteredControl();
        }

        bool success;

        // Handle any solver preOps, if necessary
        if (config.needsPreSolver()) {
            bytes memory data = forwardSpecial(
                abi.encodeWithSelector(IDAppControl.preSolverCall.selector, solverOp, returnData),
                ExecutionPhase.PreSolver
            );

            (success, data) = control.delegatecall(data);

            if (!success) {
                revert AtlasErrors.PreSolverFailed();
            }

            success = abi.decode(data, (bool));
            if (!success) {
                revert AtlasErrors.PreSolverFailed();
            }

            // Verify that the hook didn't illegally enter the Solver contract
            // success = "calledBack"
            (, success,) = IEscrow(atlas).solverLockData();
            if (success) revert AtlasErrors.InvalidEntry();
        }

        // Execute the solver call.
        bytes memory solverCallData = abi.encodeWithSelector(
            ISolverContract.atlasSolverCall.selector,
            solverOp.from,
            solverOp.bidToken,
            bidAmount,
            solverOp.data,
            config.forwardReturnData() ? returnData : new bytes(0)
        );
        (success,) = solverOp.solver.call{ gas: gasLimit, value: solverOp.value }(solverCallData);

        // Verify that it was successful
        if (!success) {
            revert AtlasErrors.SolverOperationReverted();
        }

        // Verify that the solver contract hit the callback
        // NOTE The balance may still be unfulfilled and handled by the PostSolver hook.
        (, success,) = IEscrow(atlas).solverLockData();
        if (!success) revert AtlasErrors.BalanceNotReconciled();

        // If this was a user intent, handle and verify fulfillment
        if (config.needsSolverPostCall()) {
            bytes memory data = forwardSpecial(
                abi.encodeWithSelector(IDAppControl.postSolverCall.selector, solverOp, returnData),
                ExecutionPhase.PostSolver
            );

            (success, data) = control.delegatecall(data);

            if (!success) {
                revert AtlasErrors.PostSolverFailed();
            }

            success = abi.decode(data, (bool));
            if (!success) {
                revert AtlasErrors.IntentUnfulfilled();
            }
        }

        uint256 endBalance = etherIsBidToken ? address(this).balance : ERC20(solverOp.bidToken).balanceOf(address(this));

        // Check if this is an on-chain, ex post bid search
        if (_bidFind()) {
            uint256 netBid;

            if (!config.invertsBidValue()) {
                netBid = endBalance - startBalance; // intentionally underflow on fail
                if (solverOp.bidAmount != 0 && netBid > solverOp.bidAmount) {
                    netBid = solverOp.bidAmount;
                    endBalance = etherIsBidToken ? netBid - solverOp.bidAmount : address(this).balance;
                } else {
                    endBalance = 0;
                }
            } else {
                netBid = startBalance - endBalance; // intentionally underflow on fail
                if (solverOp.bidAmount != 0 && netBid < solverOp.bidAmount) {
                    netBid = solverOp.bidAmount;
                    endBalance = etherIsBidToken ? solverOp.bidAmount - netBid : address(this).balance;
                } else {
                    endBalance = 0;
                }
            }

            // Contribute any surplus balance
            if (endBalance > 0) {
                IEscrow(atlas).contribute{ value: endBalance }();
            }

            // Verify payback
            (, success) = IEscrow(atlas).validateBalances();
            if (!success) revert AtlasErrors.BalanceNotReconciled();

            // Solver bid was successful, revert with highest amount.
            revert AtlasErrors.BidFindSuccessful(netBid);
        }

        // Verify that the solver paid what they bid
        if (!config.invertsBidValue()) {
            // CASE: higher bids are desired by beneficiary (E.G. amount transferred in by solver)

            // Use bidAmount arg instead of solverOp element to ensure that ex ante bid results
            // aren't tampered with or otherwise altered the second time around.
            if (endBalance < startBalance + bidAmount) {
                revert AtlasErrors.SolverBidUnpaid();
            }

            // Get ending eth balance
            endBalance = etherIsBidToken ? endBalance - bidAmount : address(this).balance;
        } else {
            // CASE: lower bids are desired by beneficiary (E.G. amount transferred out to solver)

            // Use bidAmount arg instead of solverOp element to ensure that ex ante bid results
            // aren't tampered with or otherwise altered the second time around.
            if (endBalance < startBalance - bidAmount) {
                // underflow -> revert = intended
                revert AtlasErrors.SolverBidUnpaid();
            }

            // Get ending eth balance
            endBalance = etherIsBidToken ? endBalance : address(this).balance;
        }

        // Contribute any surplus back - this may be used to validate balance.
        if (endBalance > 0) {
            IEscrow(atlas).contribute{ value: endBalance }();
        }

        // Verify that the solver repaid their msg.value
        (, success) = IEscrow(atlas).validateBalances();
        if (!success) {
            revert AtlasErrors.BalanceNotReconciled();
        }
    }

    function allocateValue(
        address bidToken,
        uint256 bidAmount,
        bytes memory allocateData
    )
        external
        onlyAtlasEnvironment(ExecutionPhase.HandlingPayments, _ENVIRONMENT_DEPTH)
        contributeSurplus
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        allocateData =
            forward(abi.encodeWithSelector(IDAppControl.allocateValueCall.selector, bidToken, bidAmount, allocateData));

        (bool success,) = _control().delegatecall(allocateData);
        require(success, "ERR-EC02 DelegateRevert");
    }

    ///////////////////////////////////////
    //  USER SUPPORT / ACCESS FUNCTIONS  //
    ///////////////////////////////////////
    function withdrawERC20(address token, uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).isUnlocked(), "ERR-EC15 EscrowLocked");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(ERC20(token), msg.sender, amount);
        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function factoryWithdrawERC20(address msgSender, address token, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).isUnlocked(), "ERR-EC15 EscrowLocked");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(ERC20(token), _user(), amount);
        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function withdrawEther(uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).isUnlocked(), "ERR-EC15 EscrowLocked");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function factoryWithdrawEther(address msgSender, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).isUnlocked(), "ERR-EC15 EscrowLocked");

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
