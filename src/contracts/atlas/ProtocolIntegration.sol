//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/GovernanceTypes.sol";

contract ProtocolIntegration {
    using CallBits for uint16;

    // NOTE: To prevent builder censorship, protocol nonces can be
    // processed in any order so long as they arent duplicated and
    // as long as the protocol opts in to it

    // protocolControl => govData
    mapping(address => GovernanceData) public governance;

    // map for tracking which EOAs are approved for a given protocol
    //     approver   userCall.to
    mapping(address => ApproverSigningData) public signatories;

    mapping(bytes32 => bytes32) public protocols;

    // Permissionlessly integrates a new protocol
    function initializeGovernance(address protocolControl) external {
        address owner = IProtocolControl(protocolControl).getProtocolSignatory();

        require(msg.sender == owner, "ERR-V50 OnlyGovernance");

        require(signatories[owner].governance == address(0), "ERR-V49 OwnerActive");

        uint16 callConfig = CallBits.buildCallConfig(protocolControl);

        governance[protocolControl] =
            GovernanceData({governance: owner, callConfig: callConfig, lastUpdate: uint64(block.number)});

        signatories[owner] = ApproverSigningData({governance: owner, enabled: true, nonce: 0});
    }

    function addSignatory(address protocolControl, address signatory) external {
        GovernanceData memory govData = governance[protocolControl];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        require(signatories[signatory].governance == address(0), "ERR-V49 SignatoryActive");

        signatories[signatory] = ApproverSigningData({governance: protocolControl, enabled: true, nonce: 0});
    }

    function removeSignatory(address protocolControl, address signatory) external {
        GovernanceData memory govData = governance[protocolControl];

        require(msg.sender == govData.governance || msg.sender == signatory, "ERR-V51 InvalidCaller");

        require(signatories[signatory].governance == govData.governance, "ERR-V52 InvalidProtocolControl");

        signatories[signatory].enabled = false;
    }

    function integrateProtocol(address protocolControl, address protocol) external {
        GovernanceData memory govData = governance[protocolControl];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 key = keccak256(abi.encode(protocolControl, protocol, govData.governance, govData.callConfig));

        protocols[key] = protocolControl.codehash;
    }

    function disableProtocol(address protocolControl, address protocol) external {
        GovernanceData memory govData = governance[protocolControl];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 key = keccak256(abi.encode(protocolControl, protocol, govData.governance, govData.callConfig));

        delete protocols[key];
    }

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce) {
        nextNonce = uint256(signatories[governanceSignatory].nonce) + 1;
    }
}
