//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IDAppControl} from "../interfaces/IDAppControl.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/GovernanceTypes.sol";

contract DAppIntegration {
    using CallBits for uint16;

    // NOTE: To prevent builder censorship, protocol nonces can be
    // processed in any order so long as they arent duplicated and
    // as long as the protocol opts in to it

    // controller => govData
    mapping(address => GovernanceData) public governance;

    // map for tracking which EOAs are approved for a given protocol
    //     approver   userOp.to
    mapping(address => ApproverSigningData) public signatories;

    mapping(bytes32 => bytes32) public dapps;

    // Permissionlessly integrates a new protocol
    function initializeGovernance(address controller) external {
        address owner = IDAppControl(controller).getDAppSignatory();

        require(msg.sender == owner, "ERR-V50 OnlyGovernance");

        require(signatories[owner].governance == address(0), "ERR-V49 OwnerActive");

        uint16 callConfig = CallBits.buildCallConfig(controller);

        governance[controller] =
            GovernanceData({governance: owner, callConfig: callConfig, lastUpdate: uint64(block.number)});

        signatories[owner] = ApproverSigningData({governance: owner, enabled: true, nonce: 0});
    }

    function addSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        require(signatories[signatory].governance == address(0), "ERR-V49 SignatoryActive");

        signatories[signatory] = ApproverSigningData({governance: controller, enabled: true, nonce: 0});
    }

    function removeSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance || msg.sender == signatory, "ERR-V51 InvalidCaller");

        require(signatories[signatory].governance == govData.governance, "ERR-V52 InvalidDAppControl");

        signatories[signatory].enabled = false;
    }

    function integrateDApp(address controller, address protocol) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 key = keccak256(abi.encode(controller, protocol, govData.governance, govData.callConfig));

        protocols[key] = controller.codehash;
    }

    function disableDApp(address controller, address protocol) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 key = keccak256(abi.encode(controller, protocol, govData.governance, govData.callConfig));

        delete protocols[key];
    }

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce) {
        nextNonce = uint256(signatories[governanceSignatory].nonce) + 1;
    }
}
