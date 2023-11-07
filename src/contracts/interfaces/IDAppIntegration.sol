//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IDAppIntegration {
    function initializeGovernance(address controller) external;

    function addSignatory(address controller, address signatory) external;

    function removeSignatory(address controller, address signatory) external;

    function integrateDApp(address dAppControl) external;

    function disableDApp(address dAppControl) external;

    function initializeNonce(address account) external;

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce);

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress);

}
