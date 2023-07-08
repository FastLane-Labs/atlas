//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import {CallChainProof} from "../types/VerificationTypes.sol";

interface IExecutionEnvironment {
    function stagingWrapper(CallChainProof calldata proof, UserCall calldata userCall)
        external
        payable
        returns (bytes memory stagingData);

    function userWrapper(UserCall calldata userCall) external payable returns (bytes memory userReturnData);

    function verificationWrapper(
        CallChainProof calldata proof,
        bytes calldata stagingReturnData,
        bytes calldata userReturnData
    ) external payable;

    function searcherMetaTryCatch(
        CallChainProof calldata proof,
        uint256 gasLimit,
        uint256 escrowBalance,
        SearcherCall calldata searcherCall
    ) external payable;

    function allocateRewards(
        BidData[] calldata bids, // Converted to memory
        PayeeData[] calldata payeeData
    ) external;

    function getUser() external pure returns (address user);
    function getControl() external pure returns (address control);
    function getConfig() external pure returns (uint16 config);
    function getEscrow() external view returns (address escrow);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;

    function factoryWithdrawERC20(address user, address token, uint256 amount) external;
    function factoryWithdrawEther(address user, uint256 amount) external;
}
