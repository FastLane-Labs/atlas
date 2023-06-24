//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    ProtocolCall,
    UserCall,
    CallChainProof,
    SearcherCall
} from "../libraries/DataTypes.sol";

interface ISafetyChecks {
    function handleVerification(
        ProtocolCall calldata protocolCall,
        bytes memory stagingData,
        bytes memory userReturnData
    ) external;

    function approvedCaller() external view returns (address);
}