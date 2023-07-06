//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import { SafetyBits } from "../libraries/SafetyBits.sol";
import { CallBits } from "../libraries/CallBits.sol"; 

import { ProtocolCall } from  "../types/CallTypes.sol";
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
            escrowKey.lockState == uint64(0),
            "ERR-SL003 AlreadyInitialized"
        );

        _escrowKey = escrowKey.initializeEscrowLock(
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
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // Unsafe calls so that it can trust the locks.
        require(escrowKey.isValidStagingLock(environment), "ERR-SL031 InvalidLockStage");
        
        // Handle staging calls, if needed
        if (protocolCall.callConfig.needsStagingCall()) {
            _escrowKey = escrowKey.holdStagingLock(protocolCall.to);
            _;
        }
        
        _escrowKey = escrowKey.turnStagingLock(environment);
    }

    modifier userLock(ProtocolCall calldata protocolCall, address environment) {
        // msg.sender is ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidUserLock(environment), "ERR-SL032 InvalidLockStage");
            
        _escrowKey = escrowKey.holdUserLock(protocolCall.to);
        _;

        _escrowKey = escrowKey.turnUserLock(environment);
    }

    modifier searcherLock(address searcherTo, address environment) {
        // msg.sender is the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidSearcherLock(environment), "ERR-SL033 InvalidLockStage");

        _escrowKey = escrowKey.holdSearcherLock(searcherTo);

        _;

        // NOTE: The searcher call will revert if the searcher does not activate the 
        // searcherSafetyCallback *within* the searcher try/catch wrapper.
        escrowKey = _escrowKey;

        // CASE: Searcher call successful
        if (escrowKey.confirmSearcherLock(environment)) {
            require(!escrowKey.makingPayments, "ERR-SL034 ImproperAccess");
            require(!escrowKey.paymentsComplete, "ERR-SL035 AlreadyPaid");
            _escrowKey = escrowKey.turnSearcherLockPayments(environment);
        
        // CASE: Searcher call unsuccessful && lock unaltered
        } else if (escrowKey.isRevertedSearcherLock(searcherTo)) {
            
            // NESTED CASE: Searcher is last searcher
            if (escrowKey.callIndex == escrowKey.callMax - 2) {
                _escrowKey = escrowKey.turnSearcherLockRefund(environment);
            
            // NESTED CASE: Searcher is not last searcher
            } else {
                _escrowKey = escrowKey.turnSearcherLockNext(environment);
            }
        
        // CASE: lock altered / Invalid lock access
        } else {
            revert("ERR-SL036 InvalidLockState");
        }
    }


    modifier paymentsLock(address environment) {
        // msg.sender is still the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidPaymentsLock(environment), "ERR-SL037 InvalidLockStage");

        _escrowKey = escrowKey.holdPaymentsLock();
        _;

        if (escrowKey.callIndex == escrowKey.callMax-1) {
            _escrowKey = escrowKey.turnPaymentsLockRefund(environment);
        
        // Next searcher
        } else {
            _escrowKey = escrowKey.turnPaymentsLockSearcher(environment);
        }
    }

    modifier refundLock(address environment) {
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidRefundLock(environment), "ERR-SL038 InvalidLockStage");
        _;
       
        _escrowKey = escrowKey.turnRefundLock(environment);
    }

    modifier verificationLock(uint16 callConfig, address environment) {
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidVerificationLock(environment), "ERR-SL039 InvalidLockStage");

        if (callConfig.needsVerificationCall()) {
            _escrowKey = escrowKey.holdVerificationLock();
            _; 

            escrowKey = _escrowKey;
            require(escrowKey.confirmVerificationLock(), "ERR-SL040 LockInvalid");
        }

        _escrowKey = escrowKey.turnVerificationLock(atlas);
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