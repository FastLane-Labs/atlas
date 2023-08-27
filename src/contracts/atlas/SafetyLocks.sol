//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {SafetyBits} from "../libraries/SafetyBits.sol";
import {CallBits} from "../libraries/CallBits.sol";

import {ProtocolCall, UserMetaTx} from "../types/CallTypes.sol";
import "../types/LockTypes.sol";
import "../types/EscrowTypes.sol";

import "forge-std/Test.sol";

contract SafetyLocks is Test {
    using SafetyBits for EscrowKey;
    using CallBits for uint16;

    address public immutable atlas;

    EscrowKey internal _escrowKey;

    address public activeEnvironment;

    constructor() {
        atlas = address(this);
    }

    function searcherSafetyCallback(address msgSender) external payable returns (bool isSafe) {
        // An external call so that searcher contracts can verify
        // that delegatecall isn't being abused.

        isSafe = msgSender == activeEnvironment;
    }

    function _initializeEscrowLocks(
        ProtocolCall calldata protocolCall,
        address executionEnvironment,
        uint8 searcherCallCount
    ) internal returns (EscrowKey memory self) {

        require(activeEnvironment == address(0), "ERR-SL003 AlreadyInitialized");

        activeEnvironment = executionEnvironment;

        self = self.initializeEscrowLock(
            protocolCall.callConfig.needsStagingCall(), searcherCallCount, executionEnvironment
        );
    }

    function _releaseEscrowLocks(EscrowKey memory self) internal {
        require(self.canReleaseEscrowLock(address(this)), "ERR-SL004 NotUnlockable");
        delete activeEnvironment;
    }

    function _stagingLock(EscrowKey memory self, ProtocolCall calldata protocolCall, address environment)
        internal
        returns (EscrowKey memory){
        
        return self.holdStagingLock(protocolCall.to);
        
    }

    modifier userLock(UserMetaTx calldata userCall, address environment) {
        // msg.sender = address(this) (inside try/catch)
        // address(this) = atlas

        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidUserLock(environment), "ERR-SL032 InvalidLockStage");

        // NOTE: the approvedCaller is set to the userCall's to so that it can callback
        // into the ExecutionEnvironment if needed.
        _escrowKey = escrowKey.holdUserLock(userCall.to);
        _;
    }

    function _openSearcherLock(address searcherTo, address environment) internal {
        // msg.sender = user EOA
        // address(this) = atlas

        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidSearcherLock(environment), "ERR-SL033 InvalidLockStage");
        _escrowKey = escrowKey.holdSearcherLock(searcherTo);
    }

    function _closeSearcherLock(address searcherTo, address environment, uint256 gasRebate) internal {
        // msg.sender = user EOA
        // address(this) = atlas

        // NOTE: The searcher call will revert if the searcher does not activate the
        // searcherSafetyCallback *within* the searcher try/catch wrapper.
        EscrowKey memory escrowKey = _escrowKey;

        // CASE: Searcher call successful
        if (escrowKey.confirmSearcherLock(environment)) {
            require(!escrowKey.makingPayments, "ERR-SL034 ImproperAccess");
            require(!escrowKey.paymentsComplete, "ERR-SL035 AlreadyPaid");
            unchecked {
                escrowKey.gasRefund += uint32(gasRebate);
                _escrowKey = escrowKey.turnSearcherLockPayments(environment);
            }

            // CASE: Searcher call unsuccessful && lock unaltered
        } else if (escrowKey.isRevertedSearcherLock(searcherTo)) {
            // TODO: rename this to not be so onerous
            if (gasRebate != 0) {
                unchecked {
                    _escrowKey.gasRefund += uint32(gasRebate);
                }
            }

            // CASE: lock altered / Invalid lock access
        } else {
            revert("ERR-SL036 InvalidLockState");
        }
    }

    modifier paymentsLock(address environment) {
        // msg.sender = user EOA
        // address(this) = atlas

        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidPaymentsLock(environment), "ERR-SL037 InvalidLockStage");
        _;
    }

    modifier verificationLock(uint16 callConfig, address environment) {
        // msg.sender = user EOA
        // address(this) = atlas

        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidVerificationLock(environment), "ERR-SL039 InvalidLockStage");

        _escrowKey = escrowKey.holdVerificationLock(atlas);

        if (callConfig.needsVerificationCall()) {
            _;
            escrowKey = _escrowKey;
            require(escrowKey.confirmVerificationLock(atlas), "ERR-SL040 LockInvalid");
        }
    }

    function _notMadJustDisappointed() internal {
        EscrowKey memory escrowKey = _escrowKey;
        _escrowKey = escrowKey.setAllSearchersFailed();
    }

    //////////////////////////////////
    ////////////  GETTERS  ///////////
    //////////////////////////////////

    function approvedCaller() external view returns (address) {
        return _escrowKey.approvedCaller;
    }

    // For the Execution Environment to confirm inside of searcher try/catch
    function confirmSafetyCallback() external view returns (bool) {
        return _escrowKey.confirmSearcherLock(msg.sender);
    }
}
