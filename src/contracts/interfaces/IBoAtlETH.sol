//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface IBoAtlETH {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}
