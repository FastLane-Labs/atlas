//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/DAppApprovalTypes.sol";

interface IExecutionEnvironment {
    function preOpsWrapper(UserOperation calldata userOp) external returns (bytes memory preOpsData);

    function userWrapper(UserOperation calldata userOp) external payable returns (bytes memory userReturnData);

    function postOpsWrapper(UserOperation calldata userOp, bool solved, bytes calldata returnData) external;

    function solverMetaTryCatch(
        uint256 bidAmount,
        uint256 gasLimit,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        bytes calldata dAppReturnData
    )
        external
        payable;

    function allocateValue(
        UserOperation calldata userOp,
        address bidToken,
        uint256 bidAmount,
        bytes memory returnData
    )
        external;

    function getUser() external pure returns (address user);
    function getControl() external pure returns (address control);
    function getConfig() external pure returns (uint32 config);
    function getEscrow() external view returns (address escrow);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;
}
