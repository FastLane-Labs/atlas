//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

interface ISafetyLocks {
    function handleVerification(
        ProtocolCall calldata protocolCall,
        bytes memory stagingData,
        bytes memory userReturnData
    ) external;

    function initializeEscrowLocks(address executionEnvironment, uint8 searcherCallCount) external;

    function approvedCaller() external view returns (address);

    function getLockState() external view returns (EscrowKey memory);

    function searcherSafetyCallback(address msgSender) external payable returns (bool isSafe);

    function confirmSafetyCallback() external view returns (bool);
}
