//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IDAppIntegration {
    function initializeGovernance(address controller) external;

    function addSignatory(address controller, address signatory) external;

    function removeSignatory(address controller, address signatory) external;

    function changeDAppGovernance(address oldGovernance, address newGovernance) external;

    function disableDApp(address dAppControl) external;

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce);

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress);

    function isDAppSignatory(address dAppControl, address signatory) external view returns (bool);

    function getDAppSignatories(address dAppControl) external view returns (address[] memory);
}
