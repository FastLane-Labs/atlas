//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { CallBits } from "../libraries/CallBits.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";

import "forge-std/Test.sol"; // TODO remove

contract DAppIntegration {
    using CallBits for uint32;

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

    // map for tracking which EOAs are approved for a given dApp
    //  keccak256(governance, signor)  => enabled
    mapping(bytes32 => bool) public signatories;

    // map that lists all signatories for a given dApp
    // controller => signatories
    mapping(address => address[]) public dAppSignatories;

    constructor(address _atlas) {
        ATLAS = _atlas;
    }

    // ---------------------------------------------------- //
    //                DApp Integration Functions            //
    // ---------------------------------------------------- //

    // Permissionlessly integrates a new dApp
    function initializeGovernance(address controller) external {
        address govAddress = IDAppControl(controller).getDAppSignatory();
        if (msg.sender != govAddress) revert AtlasErrors.OnlyGovernance();

        // Add DAppControl gov as a signatory
        bytes32 signatoryKey = keccak256(abi.encodePacked(controller, msg.sender));

        if (signatories[signatoryKey]) revert AtlasErrors.OwnerActive();

        signatories[signatoryKey] = true;
        dAppSignatories[controller].push(msg.sender);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.NewDAppSignatory(controller, govAddress, msg.sender, callConfig);
    }

    function addSignatory(address controller, address signatory) external {
        address dAppGov = IDAppControl(controller).getDAppSignatory();
        if (msg.sender != dAppGov) revert AtlasErrors.OnlyGovernance();

        _addSignatory(controller, signatory);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.NewDAppSignatory(controller, dAppGov, signatory, callConfig);
    }

    function removeSignatory(address controller, address signatory) external {
        address dAppGov = IDAppControl(controller).getDAppSignatory();
        if (msg.sender != dAppGov && msg.sender != signatory) {
            revert AtlasErrors.InvalidCaller();
        }

        _removeSignatory(controller, signatory);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.RemovedDAppSignatory(controller, dAppGov, signatory, callConfig);
    }

    // Called by the DAppControl contract on acceptGovernance when governance is transferred.
    function changeDAppGovernance(address oldGovernance, address newGovernance) external {
        address controller = msg.sender;
        bytes32 signatoryKey = keccak256(abi.encodePacked(controller, oldGovernance));
        if (!signatories[signatoryKey]) revert AtlasErrors.DAppNotEnabled();

        _removeSignatory(controller, oldGovernance);
        _addSignatory(controller, newGovernance);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.DAppGovernanceChanged(controller, oldGovernance, newGovernance, callConfig);
    }

    function disableDApp(address dAppControl) external {
        address dAppGov = IDAppControl(dAppControl).getDAppSignatory();
        if (msg.sender != dAppGov) revert AtlasErrors.OnlyGovernance();
        bytes32 signatoryKey = keccak256(abi.encodePacked(dAppControl, dAppGov));
        signatories[signatoryKey] = false;

        uint32 callConfig = IDAppControl(dAppControl).CALL_CONFIG();
        emit AtlasEvents.DAppDisabled(dAppControl, dAppGov, callConfig);
    }

    // ---------------------------------------------------- //
    //                   Internal Functions                 //
    // ---------------------------------------------------- //

    function _addSignatory(address controller, address signatory) internal {
        bytes32 signatoryKey = keccak256(abi.encodePacked(controller, signatory));
        if (signatories[signatoryKey]) revert AtlasErrors.SignatoryActive();
        signatories[signatoryKey] = true;
        dAppSignatories[controller].push(signatory);
    }

    function _removeSignatory(address controller, address signatory) internal {
        bytes32 signatoryKey = keccak256(abi.encodePacked(controller, signatory));
        delete signatories[signatoryKey];
        for (uint256 i = 0; i < dAppSignatories[controller].length; i++) {
            if (dAppSignatories[controller][i] == signatory) {
                dAppSignatories[controller][i] = dAppSignatories[controller][dAppSignatories[controller].length - 1];
                dAppSignatories[controller].pop();
                break;
            }
        }
    }

    // ---------------------------------------------------- //
    //                     View Functions                   //
    // ---------------------------------------------------- //

    function getGovFromControl(address dAppControl) external view returns (address) {
        address dAppGov = IDAppControl(dAppControl).getDAppSignatory();
        bytes32 signatoryKey = keccak256(abi.encodePacked(dAppControl, dAppGov));
        if (!signatories[signatoryKey]) revert AtlasErrors.DAppNotEnabled();
        return dAppGov;
    }

    function isDAppSignatory(address dAppControl, address signatory) external view returns (bool) {
        bytes32 signatoryKey = keccak256(abi.encodePacked(dAppControl, signatory));
        return signatories[signatoryKey];
    }

    function getDAppSignatories(address dAppControl) external view returns (address[] memory) {
        return dAppSignatories[dAppControl];
    }
}
