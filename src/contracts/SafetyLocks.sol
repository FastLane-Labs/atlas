//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import { BitStuff } from "./BitStuff.sol"; 

import { SafetyBits } from "../libraries/SafetyBits.sol"; 

import {
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    BidData,
    ProtocolCall,
    UserCall,
    CallConfig,
    EscrowKey,
    BaseLock,
    ExecutionPhase,
    SearcherSafety

} from "../libraries/DataTypes.sol";

contract SafetyLocks is BitStuff {
    using SafetyBits for EscrowKey;

    address immutable public factory;

    EscrowKey internal _escrowKey;

    constructor(address factoryAddress) {
        factory = factoryAddress;
    }

    function initializeEscrowLocks(
        address executionEnvironment,
        uint8 searcherCallCount
    ) external {
        
        EscrowKey memory escrowKey = _escrowKey;
        
        require(
            msg.sender != address(0) &&
            escrowKey.approvedCaller == address(0) &&
            escrowKey.makingPayments == false &&
            escrowKey.paymentsComplete == false &&
            escrowKey.callIndex == uint8(0) &&
            escrowKey.callMax == uint8(0) &&
            escrowKey.lockState == uint64(0),
            "ERR-ES001 AlreadyInitialized"
        );
        require(msg.sender == factory, "ERR-ES02 InvalidSender");

        _escrowKey = escrowKey.initializeEscrowLock(
            searcherCallCount,
            executionEnvironment
        );
    }

    function releaseEscrowLocks() external {
        require(
            msg.sender == factory &&
            _escrowKey.canReleaseEscrowLock(msg.sender),
            "ERR-ES001 NotUnlockable"
        );
        delete _escrowKey;
    }

    modifier stagingLock(ProtocolCall calldata protocolCall) {
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // Unsafe calls so that it can trust the locks.
        require(escrowKey.isValidStagingLock(msg.sender), "ERR-E31 InvalidLockStage");
        
        // Handle staging calls, if needed
        if (_needsStaging(protocolCall.callConfig)) {
            _escrowKey = escrowKey.holdStagingLock(protocolCall.to);
            _;
        }
        
        _escrowKey = escrowKey.turnStagingLock(msg.sender);
    }

    modifier userLock(uint16 callConfig) {
        // msg.sender is ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidUserLock(msg.sender), "ERR-E32 InvalidLockStage");
            
        _escrowKey = escrowKey.holdUserLock();
        _;

        _escrowKey = escrowKey.turnUserLock(msg.sender);
    }

    function _activateSearcherLock(
        address searcherTo
    ) internal {
        // msg.sender is the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidSearcherLock(msg.sender), "ERR-E33 InvalidLockStage");

        _escrowKey = escrowKey.holdSearcherLock(searcherTo);
    }

    function searcherSafetyCallback() external payable returns (bool isSafe) {
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
            _escrowKey = escrowKey.turnSearcherLock();
        } 
    }

    // NOTE: Searcher should have performed the safety callback, 
    // which would have updated the SearcherSafety level in escrowKey
    function _releaseSearcherLock(address searcherTo, bool makePayments) internal {
        // msg.sender is still the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.confirmSearcherLock(searcherTo), "ERR-E34 InvalidLockStage");

        // Check if the call was successful and warrants payment processing
        if (makePayments) {
            require(!escrowKey.makingPayments, "ERR-E28 ImproperAccess");
            require(!escrowKey.paymentsComplete, "ERR-E29 AlreadyPaid");

            _escrowKey = escrowKey.turnSearcherLockPayments(msg.sender);
        
        // Check if this is the final call - if so, prep for UserRefund
        // NOTE: if the payments handling preempts this conditional, 
        // we will set this flag at the end of the payment handling.
        } else if (escrowKey.callIndex == escrowKey.callMax - 2) {
            _escrowKey = escrowKey.turnSearcherLockRefund(msg.sender);
        
        // Next searcher
        } else {
            _escrowKey = escrowKey.turnSearcherLockNext(msg.sender);
        }
    }

    modifier paymentsLock() {
        // msg.sender is still the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidPaymentsLock(msg.sender), "ERR-E35 InvalidLockStage");

        _escrowKey = escrowKey.holdPaymentsLock();
        _;

        if (escrowKey.callIndex == escrowKey.callMax-2) {
            _escrowKey = escrowKey.turnPaymentsLockRefund(msg.sender);
        
        // Next searcher
        } else {
            _escrowKey = escrowKey.turnPaymentsLockSearcher(msg.sender);
        }
    }

    modifier refundLock() {
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidRefundLock(msg.sender), "ERR-E36 InvalidLockStage");
        _;
       
        _escrowKey = escrowKey.turnRefundLock(msg.sender);
    }

    modifier verificationLock(uint16 callConfig) {
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidVerificationLock(msg.sender), "ERR-E37 InvalidLockStage");

        if (_needsVerification(callConfig)) {
            _escrowKey = escrowKey.holdVerificationLock();
            _; 

            escrowKey = _escrowKey;
            require(escrowKey.confirmVerificationLock(), "ERR-E38 LockInvalid");
        }

        _escrowKey = escrowKey.turnVerificationLock(factory);
    }

      //////////////////////////////////
     ////////////  GETTERS  ///////////
    //////////////////////////////////

    function approvedCaller() external view returns (address) {
        return _escrowKey.approvedCaller;
    }

    function getLockState() external view returns (EscrowKey memory) {
        return _escrowKey;
    }
}