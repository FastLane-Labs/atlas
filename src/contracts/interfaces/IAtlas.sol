//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

interface IAtlas {
    function metacall(
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] calldata payeeData,
        SearcherCall[] calldata searcherCalls,
        Verification calldata verification
    ) external payable;

    function withdrawERC20(address token, uint256 amount, ProtocolCall memory protocolCall) external;
    function withdrawEther(uint256 amount, ProtocolCall memory protocolCall) external;

    function getEscrowAddress() external view returns (address escrowAddress);

    function getExecutionEnvironment(UserCall calldata userCall, address protocolControl)
        external
        view
        returns (address executionEnvironment);

    function userDirectVerifyProtocol(
        address userCallFrom,
        address userCallTo,
        uint256 searcherCallsLength,
        ProtocolCall calldata protocolCall,
        Verification calldata verification
    ) external returns (bool);

    function userDirectReleaseLock(address userCallFrom, bytes32 key, ProtocolCall calldata protocolCall) external;
}
