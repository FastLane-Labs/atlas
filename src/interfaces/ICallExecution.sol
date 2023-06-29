//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

interface ICallExecution {

    function withdrawERC20(address token, uint256 amount) external;
    function factoryWithdrawERC20(address user, address token, uint256 amount) external;
    function withdrawEther(uint256 amount) external;
    function factoryWithdrawEther(address user, uint256 amount) external;

    function stagingWrapper(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) external returns (bytes memory stagingData);

    function userWrapper(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData);

    function verificationWrapper(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData, 
        bytes memory userReturnData
    ) external;

    function searcherMetaTryCatch(
        CallChainProof memory proof,
        uint256 gasLimit,
        SearcherCall calldata searcherCall
    ) external;

    function allocateRewards(
        ProtocolCall calldata protocolCall,
        BidData[] memory bids, // Converted to memory
        PayeeData[] calldata payeeData
    ) external;
}