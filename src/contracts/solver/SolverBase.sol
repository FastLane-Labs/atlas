//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";

import "../types/SolverCallTypes.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

contract SolverBase {
    address public immutable WETH_ADDRESS;
    address internal immutable _owner;
    address internal immutable _atlas;

    constructor(address weth, address atlas, address owner) {
        WETH_ADDRESS = weth;
        _owner = owner;
        _atlas = atlas;
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
        virtual
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

        uint256 shortfall = IEscrow(_atlas).shortfall();

        if (shortfall < msg.value) shortfall = 0;
        else shortfall -= msg.value;

        if (msg.value > address(this).balance) {
            IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
        }

        IEscrow(_atlas).reconcile{ value: msg.value }(msg.sender, sender, shortfall);
    }

    modifier payBids(address bidToken, uint256 bidAmount) {
        _;

        // Handle bid payment
        if (bidToken == address(0)) {
            // Ether balance

            if (bidAmount > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(bidAmount - address(this).balance);
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
