//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import { SafetyBits } from "../libraries/SafetyBits.sol";
import { CallBits } from "../libraries/CallBits.sol"; 

import { ProtocolCall, UserCall } from  "../types/CallTypes.sol";
import "../types/LockTypes.sol";
import "../types/EscrowTypes.sol";

contract SafetyLocks {
    using SafetyBits for EscrowKey;
    using CallBits for uint16;

    address immutable public atlas;

    EscrowKey internal _escrowKey;

    constructor() {
        atlas = address(this);
    }

    function searcherSafetyCallback(address msgSender) external payable returns (bool isSafe) {
        // An external call so that searcher contracts can verify
        // that delegatecall isn't being abused. 
        // NOTE: Escrow would still work fine if we removed this 
        // and let searchers handle the safety on their own.  There
        // are other ways to provide the same safety guarantees on
        // the contract level. This was chosen because it provides
        // excellent safety for beginning searchers while having
        // a minimal increase in gas cost compared with other options. 

        EscrowKey memory escrowKey = _escrowKey;

        isSafe = escrowKey.isValidSearcherCallback(msg.sender);

        if (isSafe) {
            _escrowKey = escrowKey.turnSearcherLock(msgSender);
        } 
    }

    function _initializeEscrowLocks(
        ProtocolCall calldata protocolCall,
        address executionEnvironment,
        uint8 searcherCallCount
    ) internal {

        EscrowKey memory escrowKey = _escrowKey;
        
        require(
            escrowKey.approvedCaller == address(0) &&
            escrowKey.makingPayments == false &&
            escrowKey.paymentsComplete == false &&
            escrowKey.callIndex == uint8(0) &&
            escrowKey.callMax == uint8(0) &&
            escrowKey.lockState == uint16(0) &&
            escrowKey.gasRefund == uint32(0),
            "ERR-SL003 AlreadyInitialized"
        );

        _escrowKey = escrowKey.initializeEscrowLock(
            protocolCall.callConfig.needsStagingCall(),
            searcherCallCount,
            executionEnvironment
        );
        
    }

    function _releaseEscrowLocks() internal {
        require(
            _escrowKey.canReleaseEscrowLock(address(this)),
            "ERR-SL004 NotUnlockable"
        );
        delete _escrowKey;
    }

    modifier stagingLock(ProtocolCall calldata protocolCall, address environment) {
        // msg.sender = user EOA
        // address(this) = atlas

        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // Unsafe calls so that it can trust the locks.
        require(escrowKey.isValidStagingLock(environment), "ERR-SL031 InvalidLockStage");
        
        // Handle staging calls, if needed
        if (protocolCall.callConfig.needsStagingCall()) {
            _escrowKey = escrowKey.holdStagingLock(protocolCall.to);
            _;
        }
    }

    modifier userLock(UserCall calldata userCall, address environment) {
        // msg.sender = user EOA
        // address(this) = atlas

        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidUserLock(environment), "ERR-SL032 InvalidLockStage");
        require(userCall.from == msg.sender, "ERR-SL070 SenderNotFrom");
            
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
        } else if (escrowKey.isRevertedSearcherLock(searcherTo)) { // TODO: rename this to not be so onerous
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

    function getLockState() external view returns (EscrowKey memory) {
        return _escrowKey;
    }
}