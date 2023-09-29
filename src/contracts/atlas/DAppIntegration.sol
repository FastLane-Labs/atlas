//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IDAppControl} from "../interfaces/IDAppControl.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/GovernanceTypes.sol";

contract DAppIntegration {

    event NewDAppSignatory(
        address indexed controller,
        address indexed governance,
        address indexed signatory,
        uint32 callConfig
    );



    using CallBits for uint32;

    // NOTE: To prevent builder censorship, dapp nonces can be
    // processed in any order so long as they arent duplicated and
    // as long as the dapp opts in to it

    // controller => govData
    mapping(address => GovernanceData) public governance;

    // map for tracking which EOAs are approved for a given dapp
    //     signor   ApproverSigningData
    mapping(address => ApproverSigningData) public signatories;

    mapping(bytes32 => bytes32) public dapps;

    // Permissionlessly integrates a new dapp
    function initializeGovernance(address controller) external {
        address govAddress = IDAppControl(controller).getDAppSignatory();

        require(msg.sender == govAddress, "ERR-V50 OnlyGovernance");

        require(signatories[govAddress].governance == address(0), "ERR-V49 OwnerActive");

        uint32 callConfig = CallBits.buildCallConfig(controller);

        governance[controller] =
            GovernanceData({governance: govAddress, callConfig: callConfig, lastUpdate: uint64(block.number)});

        signatories[govAddress] = ApproverSigningData({governance: govAddress, enabled: true, nonce: 0});
    }

    function addSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        require(signatories[signatory].governance == address(0), "ERR-V49 SignatoryActive");

        signatories[signatory] = ApproverSigningData({governance: govData.governance, enabled: true, nonce: 0});
    
        emit NewDAppSignatory(
            controller,
            govData.governance,
            signatory,
            govData.callConfig
        );
    }

    function removeSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance || msg.sender == signatory, "ERR-V51 InvalidCaller");

        require(signatories[signatory].governance == govData.governance, "ERR-V52 InvalidDAppControl");

        signatories[signatory].enabled = false;
    }

    function integrateDApp(address dAppControl) external {
        GovernanceData memory govData = governance[dAppControl];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 key = keccak256(abi.encode(dAppControl, govData.governance, govData.callConfig));

        dapps[key] = dAppControl.codehash;

        emit NewDAppSignatory(
            dAppControl,
            govData.governance,
            govData.governance,
            govData.callConfig
        );
    }

    function disableDApp(address dAppControl) external {
        GovernanceData memory govData = governance[dAppControl];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 key = keccak256(abi.encode(dAppControl, govData.governance, govData.callConfig));

        delete dapps[key];
    }

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce) {
        ApproverSigningData memory signingData = signatories[governanceSignatory];
        require(signingData.enabled, "ERR-V51 SignorNotEnabled");
        nextNonce = uint256(signingData.nonce) + 1;
    }

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress) {
        GovernanceData memory govData = governance[dAppControl];
        require(govData.lastUpdate != uint64(0), "ERR-V52 DAppNotEnabled");
        governanceAddress = govData.governance;
    }

    function getGovFromSignor(address signor) external view returns (address governanceAddress) {
        ApproverSigningData memory signingData = signatories[signor];
        require(signingData.enabled, "ERR-V53 SignorNotEnabled");
        governanceAddress = signingData.governance;
    }
}
