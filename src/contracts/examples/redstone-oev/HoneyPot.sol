// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract HoneyPot is Ownable {
    struct HoneyPotDetails {
        int256 currentPrice;
        uint256 balance;
    }

    mapping(address => HoneyPotDetails) public honeyPots;
    address public oracle; // Oval serving as a Chainlink oracle
    address public settlementToken;

    event OracleUpdated(address indexed newOracle);
    event HoneyPotCreated(address indexed owner, int256 initialPrice, uint256 amount);
    event HoneyPotEmptied(address indexed owner, address indexed liquidator, uint256 amount);
    event HoneyPotReset(address indexed owner, uint256 amount);

    constructor(address _owner, address _oracle, address _settlementToken) Ownable(_owner) {
        oracle = _oracle;
        settlementToken = _settlementToken;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
        emit OracleUpdated(address(_oracle));
    }

    function createHoneyPot(uint256 _amount) external payable {
        require(_amount > 0, "No value sent");

        IERC20(settlementToken).transferFrom(msg.sender, address(this), _amount);

        (, int256 currentPrice,,,) = IFeed(oracle).latestRoundData();

        honeyPots[msg.sender].currentPrice = currentPrice;
        honeyPots[msg.sender].balance = _amount;

        emit HoneyPotCreated(msg.sender, currentPrice, msg.value);
    }

    function _emptyPotForUser(address user, address recipient, int256 _currentPrice) internal returns (uint256 amount) {
        HoneyPotDetails storage userPot = honeyPots[user];

        amount = userPot.balance;
        userPot.balance = 0; // reset the balance
        userPot.currentPrice = _currentPrice; // reset the current price
        IERC20(settlementToken).transfer(recipient, amount);
    }

    function emptyHoneyPot(address user) external {
        (, int256 currentPrice,,,) = IFeed(oracle).latestRoundData();
        require(currentPrice >= 0, "Invalid price from oracle");

        HoneyPotDetails storage userPot = honeyPots[user];

        require(currentPrice != userPot.currentPrice, "Price hasn't changed");
        require(userPot.balance > 0, "No balance to withdraw");

        uint256 withdrawnAmount = _emptyPotForUser(user, msg.sender, currentPrice);
        emit HoneyPotEmptied(user, msg.sender, withdrawnAmount);
    }

    function resetPot() external onlyOwner {
        (, int256 currentPrice,,,) = IFeed(oracle).latestRoundData();
        uint256 withdrawnAmount = _emptyPotForUser(msg.sender, msg.sender, currentPrice);
        emit HoneyPotReset(msg.sender, withdrawnAmount);
    }
}
