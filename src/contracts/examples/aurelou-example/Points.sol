// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

interface IFlashLoanReceiver {
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}

contract FlashLoan is ReentrancyGuard {
    mapping(address => uint256) public poolBalance;
    uint256 public constant FLASH_LOAN_FEE = 9; // 0.09% fee
    uint256 public constant FEE_PRECISION = 10_000;

    event FlashLoanTaken(address indexed receiver, address indexed token, uint256 amount);

    error TransferFailed();
    error InsufficientBalance(uint256 available, uint256 required);
    error InvalidLoanAmount();
    error InsufficientLiquidity(uint256 available, uint256 required);
    error InvalidBalance(uint256 expected, uint256 actual);
    error FlashLoanExecutionFailed();
    error FlashLoanNotRepaid(uint256 expected, uint256 actual);

    function deposit(address token, uint256 amount) external {
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }
        poolBalance[token] += amount;
    }

    function withdraw(address token, uint256 amount) external {
        if (poolBalance[token] < amount) {
            revert InsufficientBalance({ available: poolBalance[token], required: amount });
        }
        poolBalance[token] -= amount;
        if (!IERC20(token).transfer(msg.sender, amount)) {
            revert TransferFailed();
        }
    }

    function flashLoan(address receiver, address token, uint256 amount, bytes calldata params) external nonReentrant {
        if (amount == 0) {
            revert InvalidLoanAmount();
        }
        if (poolBalance[token] < amount) {
            revert InsufficientLiquidity({ available: poolBalance[token], required: amount });
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        if (balanceBefore < amount) {
            revert InvalidBalance({ expected: amount, actual: balanceBefore });
        }

        uint256 fee = (amount * FLASH_LOAN_FEE) / FEE_PRECISION;

        IERC20(token).transfer(receiver, amount);

        if (!IFlashLoanReceiver(receiver).executeOperation(token, amount, fee, msg.sender, params)) {
            revert FlashLoanExecutionFailed();
        }

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) {
            revert FlashLoanNotRepaid({ expected: balanceBefore + fee, actual: balanceAfter });
        }

        poolBalance[token] += fee;

        emit FlashLoanTaken(receiver, token, amount);
    }
}
