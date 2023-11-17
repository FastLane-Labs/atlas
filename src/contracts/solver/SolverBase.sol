//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";

import "../types/SolverCallTypes.sol";

import "forge-std/Test.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

contract SolverBase is Test {
    address public constant WETH_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // TODO consider making these accessible (internal) for solvers which may want to use them
    address private immutable _owner;
    address private immutable _escrow;

    constructor(address atlasEscrow, address owner) {
        _owner = owner;
        _escrow = atlasEscrow;
    }

    function atlasSolverCall(
        address sender,
        address bidToken,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata extraReturnData
    )
        external
        payable
        safetyFirst(sender)
        payBids(bidToken, bidAmount)
        returns (bool success, bytes memory data)
    {
        (success, data) = address(this).call{ value: msg.value }(solverOpData);

        require(success, "CALL UNSUCCESSFUL");
    }

    modifier safetyFirst(address sender) {
        // Safety checks
        require(sender == _owner, "INVALID CALLER");
        // uint256 msgValueOwed = msg.value;

        _;

        IEscrow(_escrow).reconcile{ value: msg.value }(msg.sender, sender, type(uint256).max);
    }

    modifier payBids(address bidToken, uint256 bidAmount) {
        // Track starting balances

        uint256 bidBalance =
            bidToken == address(0) ? address(this).balance - msg.value : ERC20(bidToken).balanceOf(address(this));

        _;

        // Handle bid payment
        if (bidToken == address(0)) {
            // Ether balance

            uint256 ethOwed = bidAmount + msg.value;

            if (ethOwed > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(ethOwed - address(this).balance);
            }

            SafeTransferLib.safeTransferETH(msg.sender, bidAmount);
        } else {
            // ERC20 balance

            if (msg.value > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
            }

            SafeTransferLib.safeTransfer(ERC20(bidToken), msg.sender, bidAmount);
        }
    }
}
