//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface IExecutionEnvironment {
    function preOpsWrapper(UserCall calldata userOp)
        external
        payable
        returns (bytes memory preOpsData);

    function userWrapper(UserCall calldata userOp) external payable returns (bytes memory userReturnData);

    function postOpsWrapper(bytes calldata returnData) external payable;

    function solverMetaTryCatch(
        uint256 gasLimit,
        uint256 escrowBalance,
        SolverOperation calldata solverOp,
        bytes calldata DAppReturnData,
        bytes calldata searcherForwardData
    ) external payable;

    function allocateValue(
        BidData[] calldata bids, // Converted to memory
        bytes memory returnData
    ) external;

    function validateUserOperation(UserCall calldata uCall) external view returns (bool);

    function getUser() external pure returns (address user);
    function getControl() external pure returns (address control);
    function getConfig() external pure returns (uint32 config);
    function getEscrow() external view returns (address escrow);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;

    function factoryWithdrawERC20(address user, address token, uint256 amount) external;
    function factoryWithdrawEther(address user, uint256 amount) external;
}
