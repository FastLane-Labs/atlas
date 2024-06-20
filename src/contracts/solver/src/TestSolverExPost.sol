// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { SolverBase } from "../SolverBase.sol";

// Flashbots opensource repo
import { BlindBackrun } from "./BlindBackrun/BlindBackrun.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

contract SolverExPost is SolverBase, BlindBackrun {
    uint256 private immutable _bidPayPercent;

    constructor(
        address weth,
        address atlasEscrow,
        address owner,
        uint256 bidPayPercent
    )
        SolverBase(weth, atlasEscrow, owner)
    {
        require(bidPayPercent <= 100, "bidPayPercent must < 100");
        _bidPayPercent = bidPayPercent;
    }

    function atlasSolverCall(
        address solverOpFrom,
        address executionEnvironment,
        address bidToken,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata
    )
        external
        payable
        override(SolverBase)
        safetyFirst(executionEnvironment, solverOpFrom)
        findAndPayBids(executionEnvironment, bidToken, bidAmount)
    {
        (bool success,) = address(this).call{ value: msg.value }(solverOpData);

        require(success, "CALL UNSUCCESSFUL");
    }

    modifier findAndPayBids(address executionEnvironment, address bidToken, uint256 bidAmount) {
        // Track starting balances

        // Starting Balance
        uint256 balance =
            bidToken == address(0) ? address(this).balance - msg.value : ERC20(bidToken).balanceOf(address(this));

        _;

        // Calculate profit
        balance = (
            bidToken == address(0) ? address(this).balance - msg.value : ERC20(bidToken).balanceOf(address(this))
        ) - balance;

        // Handle bid payment
        if (bidToken == address(0)) {
            // Ether balance
            uint256 ethOwed;

            if (bidAmount == 0) {
                ethOwed = (balance * _bidPayPercent / 100) + msg.value;
            } else {
                ethOwed = bidAmount + msg.value;
            }

            if (ethOwed > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(ethOwed - address(this).balance);
            }

            SafeTransferLib.safeTransferETH(executionEnvironment, ethOwed);
        } else {
            // ERC20 balance

            if (msg.value > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
            }

            if (bidAmount == 0) {
                SafeTransferLib.safeTransfer(ERC20(bidToken), executionEnvironment, (balance * _bidPayPercent / 100));
            } else {
                SafeTransferLib.safeTransfer(ERC20(bidToken), executionEnvironment, bidAmount);
            }
        }
    }
}
