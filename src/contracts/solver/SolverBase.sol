//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ISafetyLocks } from "src/contracts/interfaces/ISafetyLocks.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";
import { ISolverContract } from "src/contracts/interfaces/ISolverContract.sol";

import "src/contracts/types/SolverCallTypes.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

contract SolverBase is ISolverContract {
    address public immutable WETH_ADDRESS;
    address internal immutable _owner;
    address internal immutable _atlas;

    constructor(address weth, address atlas, address owner) {
        WETH_ADDRESS = weth;
        _owner = owner;
        _atlas = atlas;
    }

    function atlasSolverCall(
        address solverOpFrom,
        address executionEnvironment,
        address bidToken,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata extraReturnData
    )
        external
        payable
        virtual
        safetyFirst(executionEnvironment, solverOpFrom)
        payBids(executionEnvironment, bidToken, bidAmount)
        returns (bool success, bytes memory data)
    {
        (success, data) = address(this).call{ value: msg.value }(solverOpData);

        require(success, "CALL UNSUCCESSFUL");
    }

    modifier safetyFirst(address executionEnvironment, address solverOpFrom) {
        // Safety checks
        require(msg.sender == _atlas, "INVALID ENTRY");
        require(solverOpFrom == _owner, "INVALID CALLER");

        _;

        uint256 shortfall = IEscrow(_atlas).shortfall();

        if (shortfall < msg.value) shortfall = 0;
        else shortfall -= msg.value;

        IEscrow(_atlas).reconcile{ value: msg.value }(executionEnvironment, solverOpFrom, shortfall);
    }

    modifier payBids(address executionEnvironment, address bidToken, uint256 bidAmount) {
        _;

        // After the solverCall logic has executed, pay the solver's bid to the Execution Environment of the current
        // metacall tx.

        if (bidToken == address(0)) {
            // Pay bid in ETH

            uint256 ethOwed = bidAmount + msg.value;

            if (ethOwed > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(ethOwed - address(this).balance);
            }

            SafeTransferLib.safeTransferETH(executionEnvironment, bidAmount);
        } else {
            // Pay bid in ERC20 (bidToken)

            if (msg.value > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
            }

            SafeTransferLib.safeTransfer(ERC20(bidToken), executionEnvironment, bidAmount);
        }
    }
}
