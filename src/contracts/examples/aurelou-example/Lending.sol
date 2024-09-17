// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Lending is ReentrancyGuard {
    struct UserAccount {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 lastInterestUpdate;
    }

    IERC20 public collateralToken;
    IERC20 public lendingToken;

    mapping(address => UserAccount) public userAccounts;

    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateralization ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 125; // 125% liquidation threshold
    uint256 public constant INTEREST_RATE = 5; // 5% annual interest rate
    uint256 public constant INTEREST_RATE_DENOMINATOR = 100;
    uint256 public constant SECONDS_PER_YEAR = 31_536_000; // 365 days

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed user, address indexed liquidator, uint256 amount);

    constructor(address _collateralToken, address _lendingToken) {
        collateralToken = IERC20(_collateralToken);
        lendingToken = IERC20(_lendingToken);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit amount must be greater than zero");
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        userAccounts[msg.sender].collateralAmount = userAccounts[msg.sender].collateralAmount + (amount);

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Withdraw amount must be greater than zero");
        require(userAccounts[msg.sender].collateralAmount >= amount, "Insufficient collateral");

        updateInterest(msg.sender);

        uint256 allowedWithdrawal = _calculateAllowedWithdrawal(msg.sender);
        require(amount <= allowedWithdrawal, "Withdrawal would put account below collateral ratio");

        userAccounts[msg.sender].collateralAmount = userAccounts[msg.sender].collateralAmount - (amount);

        require(collateralToken.transfer(msg.sender, amount), "Transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "Borrow amount must be greater than zero");

        updateInterest(msg.sender);

        uint256 allowedBorrow = _calculateAllowedBorrow(msg.sender);
        require(amount <= allowedBorrow, "Borrow amount exceeds allowed amount");

        userAccounts[msg.sender].borrowedAmount = userAccounts[msg.sender].borrowedAmount + (amount);
        require(lendingToken.transfer(msg.sender, amount), "Transfer failed");

        emit Borrow(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        require(amount > 0, "Repay amount must be greater than zero");

        updateInterest(msg.sender);

        uint256 debt = userAccounts[msg.sender].borrowedAmount;
        uint256 repayAmount = amount > debt ? debt : amount;

        require(lendingToken.transferFrom(msg.sender, address(this), repayAmount), "Transfer failed");
        userAccounts[msg.sender].borrowedAmount = userAccounts[msg.sender].borrowedAmount - (repayAmount);

        emit Repay(msg.sender, repayAmount);
    }

    function liquidate(address user) external nonReentrant {
        updateInterest(user);

        require(_canLiquidate(user), "Account is not eligible for liquidation");

        uint256 debt = userAccounts[user].borrowedAmount;
        uint256 collateral = userAccounts[user].collateralAmount;

        userAccounts[user].borrowedAmount = 0;
        userAccounts[user].collateralAmount = 0;

        require(lendingToken.transferFrom(msg.sender, address(this), debt), "Debt transfer failed");
        require(collateralToken.transfer(msg.sender, collateral), "Collateral transfer failed");

        emit Liquidate(user, msg.sender, collateral);
    }

    function updateInterest(address user) public {
        UserAccount storage account = userAccounts[user];
        if (account.borrowedAmount == 0) {
            account.lastInterestUpdate = block.timestamp;
            return;
        }

        uint256 timePassed = block.timestamp - (account.lastInterestUpdate);
        uint256 interest =
            account.borrowedAmount * (INTEREST_RATE) * (timePassed) / (INTEREST_RATE_DENOMINATOR) / (SECONDS_PER_YEAR);

        account.borrowedAmount = account.borrowedAmount + (interest);
        account.lastInterestUpdate = block.timestamp;
    }

    function _calculateAllowedWithdrawal(address user) internal view returns (uint256) {
        UserAccount storage account = userAccounts[user];
        uint256 requiredCollateral = account.borrowedAmount * (COLLATERAL_RATIO) / (100);
        if (account.collateralAmount <= requiredCollateral) {
            return 0;
        }
        return account.collateralAmount - (requiredCollateral);
    }

    function _calculateAllowedBorrow(address user) internal view returns (uint256) {
        UserAccount storage account = userAccounts[user];
        uint256 maxBorrow = account.collateralAmount * (100) / (COLLATERAL_RATIO);
        if (maxBorrow <= account.borrowedAmount) {
            return 0;
        }
        return maxBorrow - (account.borrowedAmount);
    }

    function _canLiquidate(address user) internal view returns (bool) {
        UserAccount storage account = userAccounts[user];
        uint256 collateralValue = account.collateralAmount * (100);
        uint256 debtValue = account.borrowedAmount * (LIQUIDATION_THRESHOLD);
        return collateralValue < debtValue;
    }
}
