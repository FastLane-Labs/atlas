//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";
import { ISolverContract } from "src/contracts/interfaces/ISolverContract.sol";

import "src/contracts/types/SolverCallTypes.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external payable;
}

/**
 * @title SolverBaseInvertBid
 * @notice A base contract for Solvers that work with DappControls which have set the `invertBidValue` flag to true.
 */
contract SolverBaseInvertBid is ISolverContract {
    address public immutable WETH_ADDRESS;
    address internal immutable _owner;
    address internal immutable _atlas;
    bool internal immutable _bidRetreivalRequired;

    constructor(address weth, address atlas, address owner, bool bidRetreivalRequired) {
        WETH_ADDRESS = weth;
        _owner = owner;
        _atlas = atlas;
        _bidRetreivalRequired = bidRetreivalRequired;
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
        receiveBids(executionEnvironment, bidToken, bidAmount)
    {
        (bool success,) = address(this).call{ value: msg.value }(solverOpData);

        require(success, "CALL UNSUCCESSFUL");
    }

    modifier safetyFirst(address executionEnvironment, address solverOpFrom) {
        // Safety checks
        require(msg.sender == _atlas, "INVALID ENTRY");
        require(solverOpFrom == _owner, "INVALID CALLER");

        _;

        uint256 shortfall = IAtlas(_atlas).shortfall();

        if (shortfall < msg.value) shortfall = 0;
        else shortfall -= msg.value;

        if (msg.value > address(this).balance) {
            IWETH9(WETH_ADDRESS).withdraw(msg.value - address(this).balance);
        }

        IAtlas(_atlas).reconcile{ value: msg.value }(executionEnvironment, solverOpFrom, shortfall);
    }

    modifier receiveBids(address executionEnvironment, address bidToken, uint256 bidAmount) {
        // Before the solverCall logic executes, the solver's bid must be received by the solver from the Execution
        // Environment
        if (_bidRetreivalRequired) {
            require(bidToken != address(0), "Solver cannot retrieve ETH from EE");
            SafeTransferLib.safeTransferFrom(bidToken, executionEnvironment, address(this), bidAmount);
        }
        _;
    }
}
