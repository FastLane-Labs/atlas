//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

interface IFeed {
    function latestAnswer() external view returns (int256);
}

contract HoneyPot is Ownable {
    struct HoneyPotDetails {
        int256 liquidationPrice;
        uint256 balance;
    }

    mapping(address => HoneyPotDetails) public honeyPots;
    address public oracle;

    event OracleUpdated(address indexed newOracle);
    event HoneyPotCreated(address indexed owner, int256 initialPrice, uint256 amount);
    event HoneyPotEmptied(address indexed owner, address indexed liquidator, uint256 amount);
    event HoneyPotReset(address indexed owner, uint256 amount);

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
        emit OracleUpdated(address(_oracle));
    }

    function createHoneyPot() external payable {
        require(honeyPots[msg.sender].liquidationPrice == 0, "Liquidation price already set for this user");
        require(msg.value > 0, "No value sent");

        int256 currentPrice = IFeed(oracle).latestAnswer();

        honeyPots[msg.sender].liquidationPrice = currentPrice;
        honeyPots[msg.sender].balance = msg.value;

        emit HoneyPotCreated(msg.sender, currentPrice, msg.value);
    }

    function _emptyPotForUser(address owner, address recipient) internal returns (uint256 amount) {
        HoneyPotDetails storage userPot = honeyPots[owner];

        amount = userPot.balance;
        userPot.balance = 0; // reset the balance
        userPot.liquidationPrice = 0; // reset the liquidation price

        SafeTransferLib.safeTransferETH(payable(recipient), amount);
    }

    function emptyHoneyPot(address owner) external {
        int256 currentPrice = IFeed(oracle).latestAnswer();
        require(currentPrice >= 0, "Invalid price from oracle");

        HoneyPotDetails storage userPot = honeyPots[owner];

        require(currentPrice != userPot.liquidationPrice, "Liquidation price reached for this user");
        require(userPot.balance > 0, "No balance to withdraw");

        uint256 withdrawnAmount = _emptyPotForUser(owner, msg.sender);
        emit HoneyPotEmptied(owner, msg.sender, withdrawnAmount);
    }

    function resetPot() external {
        uint256 withdrawnAmount = _emptyPotForUser(msg.sender, msg.sender);
        emit HoneyPotReset(msg.sender, withdrawnAmount);
    }
}
