//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

interface IFeed {
    function latestRound() external view returns (uint80);
    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80);
}

contract HoneyPot is Ownable {
    address public oracle;
    uint256 public MAX_LIQUIDATION_DELAY = 4;
    uint8 public LIQUIDATION_HANDOUT_PERCENT = 10;

    event HoneyPotLiquidation(address indexed liquidator, uint256 amountPaid);

    constructor(address _owner, address _oracle) {
        oracle = _oracle;
        _transferOwnership(_owner);
    }

    receive() external payable { }

    function pay(address recipient, uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, amount);
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function setLiquidationDelay(uint256 _delay) external onlyOwner {
        MAX_LIQUIDATION_DELAY = _delay;
    }

    function setLiquidationHandoutPercent(uint8 _percent) external onlyOwner {
        LIQUIDATION_HANDOUT_PERCENT = _percent;
    }

    function liquidate() external {
        (, int256 ans, uint256 oracleTimestamp,,) = IFeed(oracle).getRoundData(IFeed(oracle).latestRound());
        require(block.timestamp - oracleTimestamp <= MAX_LIQUIDATION_DELAY, "HoneyPot: Liquidation delay exceeded");
        require(ans > 0, "HoneyPot: Oracle answer is not positive");

        uint256 toPay = address(this).balance * LIQUIDATION_HANDOUT_PERCENT / 100;
        require(toPay > 0, "HoneyPot: Nothing to liquidate");

        SafeTransferLib.safeTransferETH(msg.sender, toPay);
        emit HoneyPotLiquidation(msg.sender, toPay);
    }
}
