//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface IAtlETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function balanceOfBonded(address account) external view returns (uint256);
    function balanceOfUnbonding(address account) external view returns (uint256);
    function accountLastActiveBlock(address account) external view returns (uint256 lastBlock);
    function unbondingCompleteBlock(address account) external view returns (uint256);

    function bond(uint256 amount) external;
    function depositAndBond(uint256 amountToBond) external payable;
    function unbond(uint256 amount) external;
    function redeem(uint256 amount) external;
}
