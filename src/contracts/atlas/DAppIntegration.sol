//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "src/contracts/interfaces/IDAppControl.sol";
import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";

/// @title DAppIntegration
/// @author FastLane Labs
/// @notice DAppIntegration handles the integration of dApps and their signatories within the Atlas protocol.
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

    /// @notice Permissionlessly integrates a new dApp into the Atlas protocol.
    /// @param controller The address of the DAppControl contract.
    function initializeGovernance(address controller) external {
        _checkAtlasIsUnlocked();
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

    /// @notice Adds a new signatory to a dApp's list of approved signatories.
    /// @param controller The address of the DAppControl contract.
    /// @param signatory The address of the new signatory.
    function addSignatory(address controller, address signatory) external {
        _checkAtlasIsUnlocked();
        address dAppGov = IDAppControl(controller).getDAppSignatory();
        if (msg.sender != dAppGov) revert AtlasErrors.OnlyGovernance();

        _addSignatory(controller, signatory);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.NewDAppSignatory(controller, dAppGov, signatory, callConfig);
    }

    /// @notice Removes a signatory from a dApp's list of approved signatories.
    /// @param controller The address of the DAppControl contract.
    function removeSignatory(address controller, address signatory) external {
        _checkAtlasIsUnlocked();
        address dAppGov = IDAppControl(controller).getDAppSignatory();
        if (msg.sender != dAppGov && msg.sender != signatory) {
            revert AtlasErrors.InvalidCaller();
        }

        _removeSignatory(controller, signatory);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.RemovedDAppSignatory(controller, dAppGov, signatory, callConfig);
    }

    /// @notice Called by the DAppControl contract on acceptGovernance when governance is transferred.
    /// @dev Must be called by the DAppControl contract concerned and Atlas must be in an unlocked state.
    /// @param oldGovernance The address of the old governance.
    /// @param newGovernance The address of the new governance.
    function changeDAppGovernance(address oldGovernance, address newGovernance) external {
        _checkAtlasIsUnlocked();
        address controller = msg.sender;
        bytes32 signatoryKey = keccak256(abi.encodePacked(controller, oldGovernance));
        if (!signatories[signatoryKey]) revert AtlasErrors.DAppNotEnabled();

        _removeSignatory(controller, oldGovernance);
        _addSignatory(controller, newGovernance);

        uint32 callConfig = IDAppControl(controller).CALL_CONFIG();
        emit AtlasEvents.DAppGovernanceChanged(controller, oldGovernance, newGovernance, callConfig);
    }

    /// @notice Disables a dApp from the Atlas protocol.
    /// @param dAppControl The address of the DAppControl contract.
    function disableDApp(address dAppControl) external {
        _checkAtlasIsUnlocked();
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

    /// @notice Adds a new signatory to a dApp's list of approved signatories.
    /// @param controller The address of the DAppControl contract.
    /// @param signatory The address of the new signatory.
    function _addSignatory(address controller, address signatory) internal {
        bytes32 signatoryKey = keccak256(abi.encodePacked(controller, signatory));
        if (signatories[signatoryKey]) revert AtlasErrors.SignatoryActive();
        signatories[signatoryKey] = true;
        dAppSignatories[controller].push(signatory);
    }

    /// @notice Removes a signatory from a dApp's list of approved signatories.
    /// @param controller The address of the DAppControl contract.
    /// @param signatory The address of the signatory to be removed.
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

    /// @notice Checks if the Atlas protocol is in an unlocked state. Will revert if not.
    function _checkAtlasIsUnlocked() internal view {
        if (!IAtlas(ATLAS).isUnlocked()) revert AtlasErrors.AtlasLockActive();
    }

    // ---------------------------------------------------- //
    //                     View Functions                   //
    // ---------------------------------------------------- //

    /// @notice Returns the governance address of a specified DAppControl contract.
    /// @param dAppControl The address of the DAppControl contract.
    /// @return The governance address of the specified DAppControl contract.
    function getGovFromControl(address dAppControl) external view returns (address) {
        address dAppGov = IDAppControl(dAppControl).getDAppSignatory();
        bytes32 signatoryKey = keccak256(abi.encodePacked(dAppControl, dAppGov));
        if (!signatories[signatoryKey]) revert AtlasErrors.DAppNotEnabled();
        return dAppGov;
    }

    /// @notice Returns whether a specified address is a signatory for a specified DAppControl contract.
    /// @param dAppControl The address of the DAppControl contract.
    /// @param signatory The address to check.
    /// @return A boolean indicating whether the specified address is a signatory for the specified DAppControl
    /// contract.
    function isDAppSignatory(address dAppControl, address signatory) external view returns (bool) {
        bytes32 signatoryKey = keccak256(abi.encodePacked(dAppControl, signatory));
        return signatories[signatoryKey];
    }

    /// @notice Returns an array of signatories for a specified DAppControl contract.
    /// @param dAppControl The address of the DAppControl contract.
    /// @return An array of signatories for the specified DAppControl contract.
    function getDAppSignatories(address dAppControl) external view returns (address[] memory) {
        return dAppSignatories[dAppControl];
    }
}
