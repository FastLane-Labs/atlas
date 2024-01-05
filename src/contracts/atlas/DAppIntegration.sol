//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IDAppControl } from "../interfaces/IDAppControl.sol";

import { CallBits } from "../libraries/CallBits.sol";

import "../types/GovernanceTypes.sol";

import { FastLaneErrorsEvents } from "../types/Emissions.sol";

contract DAppIntegration {
    using CallBits for uint32;

    event NewDAppSignatory(
        address indexed controller, address indexed governance, address indexed signatory, uint32 callConfig
    );

    struct NonceBitmap {
        uint8 highestUsedNonce;
        uint240 bitmap;
    }

    struct NonceTracker {
        uint128 LowestEmptyBitmap;
        uint128 HighestFullBitmap;
    }

    address public immutable ATLAS;

    //     from         nonceTracker
    mapping(address => NonceTracker) public asyncNonceBitIndex;

    //  keccak256(from, bitmapNonceIndex) => to
    mapping(bytes32 => NonceBitmap) public asyncNonceBitmap;

    // NOTE: To prevent builder censorship, dapp nonces can be
    // processed in any order so long as they arent duplicated and
    // as long as the dapp opts in to it

    // controller => govData
    mapping(address => GovernanceData) public governance;

    // map for tracking which EOAs are approved for a given dapp
    //  keccak256(governance, signor)  => enabled
    mapping(bytes32 => bool) public signatories;

    mapping(bytes32 => bytes32) public dapps;

    constructor(address _atlas) {
        ATLAS = _atlas;
    }

    // Permissionlessly integrates a new dapp
    function initializeGovernance(address controller) external {
        address govAddress = IDAppControl(controller).getDAppSignatory();

        if (msg.sender != govAddress) revert FastLaneErrorsEvents.OnlyGovernance();

        bytes32 signatoryKey = keccak256(abi.encode(msg.sender, controller));

        if (signatories[signatoryKey]) revert FastLaneErrorsEvents.OwnerActive();

        uint32 callConfig = CallBits.buildCallConfig(controller);

        governance[controller] =
            GovernanceData({ governance: govAddress, callConfig: callConfig, lastUpdate: uint64(block.number) });

        signatories[signatoryKey] = true;

        _initializeNonce(msg.sender);
    }

    function addSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        if (msg.sender != govData.governance) revert FastLaneErrorsEvents.OnlyGovernance();

        bytes32 signatoryKey = keccak256(abi.encode(msg.sender, signatory));

        if (signatories[signatoryKey]) {
            revert FastLaneErrorsEvents.SignatoryActive();
        }

        signatories[signatoryKey] = true;

        _initializeNonce(signatory);

        emit NewDAppSignatory(controller, govData.governance, signatory, govData.callConfig);
    }

    function removeSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        if (msg.sender != govData.governance && msg.sender != signatory) {
            revert FastLaneErrorsEvents.InvalidCaller();
        }

        bytes32 signatoryKey = keccak256(abi.encode(govData.governance, signatory));

        if (!signatories[signatoryKey]) revert FastLaneErrorsEvents.InvalidDAppControl();

        delete signatories[signatoryKey];
    }

    function integrateDApp(address dAppControl) external {
        GovernanceData memory govData = governance[dAppControl];

        if (msg.sender != govData.governance) revert FastLaneErrorsEvents.OnlyGovernance();

        bytes32 key = keccak256(abi.encode(dAppControl, govData.governance, govData.callConfig));

        dapps[key] = dAppControl.codehash;

        emit NewDAppSignatory(dAppControl, govData.governance, govData.governance, govData.callConfig);
    }

    function disableDApp(address dAppControl) external {
        GovernanceData memory govData = governance[dAppControl];

        if (msg.sender != govData.governance) revert FastLaneErrorsEvents.OnlyGovernance();

        bytes32 key = keccak256(abi.encode(dAppControl, govData.governance, govData.callConfig));

        delete dapps[key];
    }

    function initializeNonce(address account) external {
        _initializeNonce(account);
    }

    function _initializeNonce(address account) internal returns (bool initialized) {
        if (asyncNonceBitIndex[account].LowestEmptyBitmap == uint128(0)) {
            unchecked {
                asyncNonceBitIndex[account].LowestEmptyBitmap = 2;
            }
            bytes32 bitmapKey = keccak256(abi.encode(account, 1));

            // to skip the 0 nonce
            asyncNonceBitmap[bitmapKey] = NonceBitmap({ highestUsedNonce: uint8(1), bitmap: 0 });
            initialized = true;
        }
    }

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress) {
        GovernanceData memory govData = governance[dAppControl];
        if (govData.lastUpdate == 0) revert FastLaneErrorsEvents.DAppNotEnabled();
        governanceAddress = govData.governance;
    }
}
