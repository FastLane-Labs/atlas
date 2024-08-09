//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// External representation of the swap intent
struct SwapIntent {
    address tokenUserBuys;
    uint256 minAmountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
}

struct BaselineCall {
    address to; // Address to send the swap if there are no solvers / to get the baseline
    bytes data; // Calldata for the baseline swap
    bool success; // Records or not the first baseline call was successful
}
