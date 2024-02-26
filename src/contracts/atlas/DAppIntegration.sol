//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "../interfaces/IDAppControl.sol";

import { CallBits } from "../libraries/CallBits.sol";

import "../types/GovernanceTypes.sol";

import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "forge-std/Test.sol"; // TODO remove

contract DAppIntegration {
    using CallBits for uint32;

    event NewDAppSignatory(
        address indexed controller, address indexed governance, address indexed signatory, uint32 callConfig
    );

    event RemovedDAppSignatory(
        address indexed controller, address indexed governance, address indexed signatory, uint32 callConfig
    );

    struct NonceBitmap {
        uint8 highestUsedNonce;
        uint240 bitmap;
    }

    struct NonceTracker {
        uint128 lastUsedSeqNonce; // Sequenced nonces tracked using only this value
        uint128 highestFullAsyncBitmap; // Async nonces tracked using bitmaps
    }

    address public immutable ATLAS;

    // from => nonceTracker
    mapping(address => NonceTracker) public nonceTrackers;

    // keccak256(from, bitmapNonceIndex) => nonceBitmap
    mapping(bytes32 => NonceBitmap) public nonceBitmaps;

    // NOTE: To prevent builder censorship, dApp nonces can be
    // processed in any order so long as they arent duplicated and
    // as long as the dApp opts in to it

    // controller => govData
    mapping(address => GovernanceData) public governance;

    // map for tracking which EOAs are approved for a given dApp
    //  keccak256(governance, signor)  => enabled
    mapping(bytes32 => bool) public signatories;

    // map that lists all signatories for a given dApp
    // controller => signatories
    mapping(address => address[]) public dAppSignatories;

    constructor(address _atlas) {
        ATLAS = _atlas;
    }

    // Permissionlessly integrates a new dApp
    function initializeGovernance(address controller) external {
        address govAddress = IDAppControl(controller).getDAppSignatory();

        if (msg.sender != govAddress) revert AtlasErrors.OnlyGovernance();

        bytes32 signatoryKey = keccak256(abi.encodePacked(msg.sender, controller, msg.sender));

        if (signatories[signatoryKey]) revert AtlasErrors.OwnerActive();

        uint32 callConfig = CallBits.buildCallConfig(controller);

        governance[controller] =
            GovernanceData({ governance: govAddress, callConfig: callConfig, lastUpdate: uint64(block.number) });

        signatories[signatoryKey] = true;
        dAppSignatories[controller].push(msg.sender);
    }

    function addSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        if (msg.sender != govData.governance) revert AtlasErrors.OnlyGovernance();

        bytes32 signatoryKey = keccak256(abi.encodePacked(msg.sender, controller, signatory));

        if (signatories[signatoryKey]) {
            revert AtlasErrors.SignatoryActive();
        }

        signatories[signatoryKey] = true;
        dAppSignatories[controller].push(signatory);

        emit NewDAppSignatory(controller, govData.governance, signatory, govData.callConfig);
    }

    function removeSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        if (msg.sender != govData.governance && msg.sender != signatory) {
            revert AtlasErrors.InvalidCaller();
        }

        bytes32 signatoryKey = keccak256(abi.encodePacked(govData.governance, controller, signatory));

        if (!signatories[signatoryKey]) revert AtlasErrors.InvalidDAppControl();

        delete signatories[signatoryKey];
        for (uint256 i = 0; i < dAppSignatories[controller].length; i++) {
            if (dAppSignatories[controller][i] == signatory) {
                dAppSignatories[controller][i] = dAppSignatories[controller][dAppSignatories[controller].length - 1];
                dAppSignatories[controller].pop();
                break;
            }
        }

        emit RemovedDAppSignatory(controller, govData.governance, signatory, govData.callConfig);
    }

    function disableDApp(address dAppControl) external {
        GovernanceData memory govData = governance[dAppControl];

        if (msg.sender != govData.governance) revert AtlasErrors.OnlyGovernance();

        delete governance[dAppControl];
    }

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress) {
        GovernanceData memory govData = governance[dAppControl];
        if (govData.lastUpdate == 0) revert AtlasErrors.DAppNotEnabled();
        governanceAddress = govData.governance;
    }

    function getDAppSignatories(address dAppControl) external view returns (address[] memory) {
        return dAppSignatories[dAppControl];
    }
}
