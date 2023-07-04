//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import { CallChainProof } from "../types/VerificationTypes.sol";

interface IExecutionEnvironment {
    
    function stagingWrapper(
        CallChainProof calldata proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) external payable returns (bytes memory stagingData);

    function userWrapper(
        CallChainProof calldata proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData);

    function verificationWrapper(
        CallChainProof calldata proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData, 
        bytes memory userReturnData
    ) payable external;

    function searcherMetaTryCatch(
        CallChainProof calldata proof,
        uint256 gasLimit,
        uint256 escrowBalance,
        SearcherCall calldata searcherCall
    ) payable external;

    function allocateRewards(
        ProtocolCall calldata protocolCall,
        BidData[] calldata bids, // Converted to memory
        PayeeData[] calldata payeeData
    ) external;

    function getUser() external view returns (address _user);
    function getFactory() external view returns (address _factory);
    function getEscrow() external view returns (address _escrow);
    function getCallConfig() external view returns (uint16 _config);

    function withdrawERC20(address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;

    function factoryWithdrawERC20(address user, address token, uint256 amount) external;
    function factoryWithdrawEther(address user, uint256 amount) external;
}