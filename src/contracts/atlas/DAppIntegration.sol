//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IDAppControl} from "../interfaces/IDAppControl.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/GovernanceTypes.sol";

contract DAppIntegration {
    using CallBits for uint32;

    event NewDAppSignatory(
        address indexed controller,
        address indexed governance,
        address indexed signatory,
        uint32 callConfig
    );

    struct NonceBitmap {
        uint8 highestUsedNonce;
        uint240 bitmap;
    }

    struct NonceTracker {
        uint128 LowestEmptyBitmap;
        uint128 HighestFullBitmap;
    }

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

    // Permissionlessly integrates a new dapp
    function initializeGovernance(address controller) external {
        address govAddress = IDAppControl(controller).getDAppSignatory();

        require(msg.sender == govAddress, "ERR-V50 OnlyGovernance");

        bytes32 signatoryKey = keccak256(abi.encode(msg.sender, msg.sender));

        require(!signatories[signatoryKey], "ERR-V49 OwnerActive");

        uint32 callConfig = CallBits.buildCallConfig(controller);

        governance[controller] =
            GovernanceData({governance: govAddress, callConfig: callConfig, lastUpdate: uint64(block.number)});

        signatories[signatoryKey] = true;

        _initializeNonce(msg.sender);
        
    }

    function addSignatory(address controller, address signatory) external {
        GovernanceData memory govData = governance[controller];

        require(msg.sender == govData.governance, "ERR-V50 OnlyGovernance");

        bytes32 signatoryKey = keccak256(abi.encode(msg.sender, signatory));

        require(!signatories[signatoryKey], "ERR-V49 SignatoryActive");

        signatories[signatoryKey] = true;
    
        _initializeNonce(signatory);

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

        bytes32 signatoryKey = keccak256(abi.encode(msg.sender, signatory));

        require(signatories[signatoryKey], "ERR-V52 InvalidDAppControl");

        delete signatories[signatoryKey];
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

    function _initializeNonce(address account) internal {
        if (asyncNonceBitIndex[account].LowestEmptyBitmap == uint128(0)) {
            unchecked {
                asyncNonceBitIndex[account].LowestEmptyBitmap = 2;
            }
            bytes32 bitmapKey = keccak256(abi.encode(account, 1));

            // to skip the 0 nonce
            asyncNonceBitmap[bitmapKey] = NonceBitmap({
                highestUsedNonce: uint8(1),
                bitmap: 0
            });
        }
    }

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress) {
        GovernanceData memory govData = governance[dAppControl];
        require(govData.lastUpdate != uint64(0), "ERR-V52 DAppNotEnabled");
        governanceAddress = govData.governance;
    }
}
