//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    ProtocolCall,
    UserCall,
    CallChainProof,
    SearcherCall,
    EscrowKey
} from "../libraries/DataTypes.sol";

interface ISafetyLocks {
    function handleVerification(
        ProtocolCall calldata protocolCall,
        bytes memory stagingData,
        bytes memory userReturnData
    ) external;

    function approvedCaller() external view returns (address);

    function getLockState() external view returns (EscrowKey memory);
}