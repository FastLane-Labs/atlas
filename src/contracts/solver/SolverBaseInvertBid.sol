//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IAtlas } from "../interfaces/IAtlas.sol";
import { ISolverContract } from "../interfaces/ISolverContract.sol";

import "../types/SolverOperation.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

/**
 * @title SolverBaseInvertBid
 * @notice A base contract for Solvers that work with DAppControls which have set the `invertBidValue` flag to true.
 */
contract SolverBaseInvertBid is ISolverContract {
    address public immutable WETH_ADDRESS;
    address internal immutable _owner;
    address internal immutable _atlas;
    bool internal immutable _bidRetrievalRequired;

    error SolverCallUnsuccessful();
    error InvalidEntry();
    error InvalidCaller();

    constructor(address weth, address atlas, address owner, bool bidRetrievalRequired) {
        WETH_ADDRESS = weth;
        _owner = owner;
        _atlas = atlas;
        _bidRetrievalRequired = bidRetrievalRequired;
    }

    function atlasSolverCall(
        address solverOpFrom,
        address executionEnvironment,
        address bidToken,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata /* extraReturnData */
    )
        external
        payable
        virtual
        safetyFirst(executionEnvironment, solverOpFrom)
        receiveBids(executionEnvironment, bidToken, bidAmount)
    {
        (bool success,) = address(this).call{ value: msg.value }(solverOpData);
        if (!success) revert SolverCallUnsuccessful();
    }

    modifier safetyFirst(address executionEnvironment, address solverOpFrom) {
        // Safety checks
        if (msg.sender != _atlas) revert InvalidEntry();
        if (solverOpFrom != _owner) revert InvalidCaller();

        _;

        (uint256 gasLiability, uint256 borrowLiability) = IAtlas(_atlas).shortfall();
        uint256 nativeRepayment = borrowLiability < msg.value ? borrowLiability : msg.value;
        IAtlas(_atlas).reconcile{ value: nativeRepayment }(gasLiability);
    }

    modifier receiveBids(address executionEnvironment, address bidToken, uint256 bidAmount) {
        // Before the solverCall logic executes, the solver's bid must be received by the solver from the Execution
        // Environment
        if (_bidRetrievalRequired) {
            require(bidToken != address(0), "Solver cannot retrieve ETH from EE");
            SafeTransferLib.safeTransferFrom(bidToken, executionEnvironment, address(this), bidAmount);
        }
        _;
    }
}
