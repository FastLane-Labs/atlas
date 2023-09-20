// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

library SwapMath {
    using SafeMath for uint256;

    function getAmountIn(uint256 amountOut, uint256 reservesIn, uint256 reservesOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        uint256 numerator = reservesIn.mul(amountOut).mul(1000);
        uint256 denominator = reservesOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
}
