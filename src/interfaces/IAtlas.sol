//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    ProtocolCall,
    UserCall,
    PayeeData,
    SearcherCall,
    Verification,
    ProtocolData
} from "../libraries/DataTypes.sol";

interface IAtlas {
    function metacall(
        ProtocolCall calldata protocolCall, // supplied by frontend
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, // supplied by frontend
        SearcherCall[] calldata searcherCalls // supplied by FastLane via frontend integration
    ) external payable;

    function untrustedVerifyProtocol(
        address userCallTo,
        uint256 searcherCallsLength,
        Verification calldata verification
    ) external returns (bool, ProtocolData memory);

    function untrustedReleaseLock(bytes32 key) external;
}