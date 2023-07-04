//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IProtocolIntegration {

    function initializeGovernance(address protocolControl) external;

    function addSignatory(address protocolControl, address signatory) external;

    function removeSignatory(address protocolControl, address signatory) external;

    function integrateProtocol(address protocolControl, address protocol) external;

    function disableProtocol(address protocolControl, address protocol) external;

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce);
    
}