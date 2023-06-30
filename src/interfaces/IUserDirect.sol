//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IUserDirect {

    function getUser() external view returns (address _user);
    function getProtocolControl() external view returns (address _control);
    function getFactory() external view returns (address _factory);
    function getEscrow() external view returns (address _escrow);
    function getCallConfig() external view returns (uint16 _config);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;
}