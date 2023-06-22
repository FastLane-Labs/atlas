//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    StagingCall,
    UserCall,
    SearcherProof,
    SearcherCall
} from "../libraries/DataTypes.sol";

interface ISafetyChecks {
    function handleVerification(
        StagingCall calldata stagingCall,
        bytes memory stagingData,
        bytes memory userReturnData
    ) external
}