// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {IUniswapV2Pair} from "../src/contracts/examples/v2-example/interfaces/IUniswapV2Pair.sol";

import {BlindBackrun} from "./solver/src/blindBackrun.sol";

import "../src/contracts/types/CallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/VerificationTypes.sol";

import {TestConstants} from "./base/TestConstants.sol";

import "forge-std/Test.sol";

contract V2Helper is Test, TestConstants, TxBuilder {
   
    uint256 public immutable maxFeePerGas;

    constructor(address controller, address escrowAddress, address atlasAddress) 
        TxBuilder(controller, escrowAddress, atlasAddress)
    {
        maxFeePerGas = tx.gasprice * 2;
    }

    function getPayeeData() public returns (PayeeData[] memory) {
        bytes memory nullData;
        return TxBuilder.getPayeeData(nullData);
    }

    function buildUserOperation(address to, address from, address tokenIn) public view returns (UserOperation memory userOp) {
        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(to).getReserves();

        address token0 = IUniswapV2Pair(to).token0();

        return TxBuilder.buildUserOperation(
            from,
            to,
            maxFeePerGas,
            0,
            buildV2SwapCalldata(
                tokenIn == token0 ? 0 : uint256(token0Balance) / 2, tokenIn == token0 ? uint256(token1Balance) / 2 : 0, from
                )
        );
    }

    function buildV2SwapCalldata(uint256 amount0Out, uint256 amount1Out, address recipient)
        public
        pure
        returns (bytes memory data)
    {
        data = abi.encodeWithSelector(IUniswapV2Pair.swap.selector, amount0Out, amount1Out, recipient, data);
    }

    function buildV2SolverOperationData(
        address poolOne,
        address poolTwo
    ) public pure returns (bytes memory data) {
        data = abi.encodeWithSelector(BlindBackrun.executeArbitrage.selector, poolOne, poolTwo);
    }
}
