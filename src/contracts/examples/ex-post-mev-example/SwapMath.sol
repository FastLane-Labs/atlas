// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

library SwapMath {
    function getAmountIn(
        uint256 amountOut,
        uint256 reservesIn,
        uint256 reservesOut
    )
        internal
        pure
        returns (uint256 amountIn)
    {
        uint256 numerator = reservesIn * amountOut * 1000;
        uint256 denominator = (reservesOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
}
