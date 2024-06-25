//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { ISafetyLocks } from "src/contracts/interfaces/ISafetyLocks.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";
import { ISolverContract } from "src/contracts/interfaces/ISolverContract.sol";

import "src/contracts/types/SolverCallTypes.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

/**
 * @title SolverBase
 * @notice A base contract for Solvers
 * @dev Does safety checks, escrow reconciliation and pays bids.
 * @dev Works with DappControls which have set the `invertBidValue` flag to false.
 * @dev Use `SolverBaseInvertBid` for DappControls which have set the `invertBidValue` flag to true.
 */
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
        bytes calldata
    )
        external
        payable
        virtual
        safetyFirst(executionEnvironment, solverOpFrom)
        payBids(executionEnvironment, bidToken, bidAmount)
    {
        (bool success,) = address(this).call{ value: msg.value }(solverOpData);

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

        if (msg.value > address(this).balance) {
            IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
        }

        IEscrow(_atlas).reconcile{ value: msg.value }(executionEnvironment, solverOpFrom, shortfall);
    }

    modifier payBids(address executionEnvironment, address bidToken, uint256 bidAmount) {
        _;

        // After the solverCall logic has executed, pay the solver's bid to the Execution Environment of the current
        // metacall tx.

        if (bidToken == address(0)) {
            // Pay bid in ETH

            if (bidAmount > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(bidAmount - address(this).balance);
            }

            SafeTransferLib.safeTransferETH(executionEnvironment, bidAmount);
        } else {
            // Pay bid in ERC20 (bidToken)

            if (msg.value > address(this).balance) {
                IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
            }

            SafeTransferLib.safeTransfer(bidToken, executionEnvironment, bidAmount);
        }
    }
}
