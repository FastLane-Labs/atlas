//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

interface IExecutionEnvironment {
    function preOpsWrapper(UserOperation calldata userOp)
        external
        payable
        returns (bytes memory preOpsData);

    function userWrapper(UserOperation calldata userOp) external payable returns (bytes memory userReturnData);

    function postOpsWrapper(bytes calldata returnData) external payable;

    function solverMetaTryCatch(
        uint256 gasLimit,
        SolverOperation calldata solverOp,
        bytes calldata dAppReturnData
    ) external payable;

    function allocateValue(address bidToken, uint256 bidAmount, bytes memory returnData) 
        external;

    function getUser() external pure returns (address user);
    function getControl() external pure returns (address control);
    function getConfig() external pure returns (uint32 config);
    function getEscrow() external view returns (address escrow);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;

    function factoryWithdrawERC20(address user, address token, uint256 amount) external;
    function factoryWithdrawEther(address user, uint256 amount) external;
}
