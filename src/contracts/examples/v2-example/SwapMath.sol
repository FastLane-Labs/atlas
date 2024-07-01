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

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        internal
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
