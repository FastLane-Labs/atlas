//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface IExecutionEnvironment {
    function stagingWrapper(UserMetaTx calldata userCall)
        external
        payable
        returns (bytes memory stagingData);

    function userWrapper(UserMetaTx calldata userCall) external payable returns (bytes memory userReturnData);

    function verificationWrapper(bytes calldata returnData) external payable;

    function searcherMetaTryCatch(
        uint256 gasLimit,
        uint256 escrowBalance,
        SearcherCall calldata searcherCall,
        bytes calldata returnData
    ) external payable;

    function allocateRewards(
        BidData[] calldata bids, // Converted to memory
        bytes memory returnData
    ) external;

    function validateUserCall(UserMetaTx calldata userMetaTx) external view returns (bool);

    function getUser() external pure returns (address user);
    function getControl() external pure returns (address control);
    function getConfig() external pure returns (uint16 config);
    function getEscrow() external view returns (address escrow);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;

    function factoryWithdrawERC20(address user, address token, uint256 amount) external;
    function factoryWithdrawEther(address user, uint256 amount) external;
}
