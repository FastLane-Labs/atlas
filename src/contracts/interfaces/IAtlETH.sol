//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IAtlETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}
