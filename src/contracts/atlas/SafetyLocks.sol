//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import { SafetyBits } from "../libraries/SafetyBits.sol";
import { CallBits } from "../libraries/CallBits.sol"; 

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

import "forge-std/Test.sol";

contract SafetyLocks is Test {
    using SafetyBits for EscrowKey;
    using CallBits for uint16;

    address immutable public factory;

    EscrowKey internal _escrowKey;

    constructor(address factoryAddress) {
        factory = factoryAddress;
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

    function initializeEscrowLocks(
        address executionEnvironment,
        uint8 searcherCallCount
    ) external {
        require(msg.sender == factory, "ERR-SL002 InvalidSender");

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

    function releaseEscrowLocks() external {
        require(
            msg.sender == factory &&
            _escrowKey.canReleaseEscrowLock(msg.sender),
            "ERR-SL004 NotUnlockable"
        );
        delete _escrowKey;
    }

    modifier stagingLock(ProtocolCall calldata protocolCall) {
        // msg.sender = ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // Unsafe calls so that it can trust the locks.
        require(escrowKey.isValidStagingLock(msg.sender), "ERR-SL031 InvalidLockStage");
        
        // Handle staging calls, if needed
        if (protocolCall.callConfig.needsStagingCall()) {
            _escrowKey = escrowKey.holdStagingLock(protocolCall.to);
            _;
        }
        
        _escrowKey = escrowKey.turnStagingLock(msg.sender);
    }

    modifier userLock(ProtocolCall calldata protocolCall) {
        // msg.sender is ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidUserLock(msg.sender), "ERR-SL032 InvalidLockStage");
            
        _escrowKey = escrowKey.holdUserLock(protocolCall.to);
        _;

        _escrowKey = escrowKey.turnUserLock(msg.sender);
    }

    modifier searcherLock(address searcherTo) {
        // msg.sender is the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        console.log("searcher lock A-0");

        require(escrowKey.isValidSearcherLock(msg.sender), "ERR-SL033 InvalidLockStage");

        console.log("searcher lock A-1");
        _escrowKey = escrowKey.holdSearcherLock(searcherTo);

        _;

        // NOTE: The searcher call will revert if the searcher does not activate the 
        // searcherSafetyCallback *within* the searcher try/catch wrapper.
        escrowKey = _escrowKey;

        console.log("searcher lock A-2");
        // CASE: Searcher call successful
        if (escrowKey.confirmSearcherLock(msg.sender)) {
            console.log("searcher lock A-2-0a");
            require(!escrowKey.makingPayments, "ERR-SL034 ImproperAccess");
            console.log("searcher lock A-2-1a");
            require(!escrowKey.paymentsComplete, "ERR-SL035 AlreadyPaid");
            console.log("searcher lock A-2-2a");
            _escrowKey = escrowKey.turnSearcherLockPayments(msg.sender);
        
        // CASE: Searcher call unsuccessful && lock unaltered
        } else if (escrowKey.isRevertedSearcherLock(searcherTo)) {
            
            console.log("searcher lock A-2-0b");
            // NESTED CASE: Searcher is last searcher
            if (escrowKey.callIndex == escrowKey.callMax - 2) {
                console.log("searcher lock A-2-0b-0a");
                _escrowKey = escrowKey.turnSearcherLockRefund(msg.sender);
            
            // NESTED CASE: Searcher is not last searcher
            } else {
                console.log("searcher lock A-2-0b-0b");
                _escrowKey = escrowKey.turnSearcherLockNext(msg.sender);
            }
        
        // CASE: lock altered / Invalid lock access
        } else {
            console.log("searcher lock A-2-0c");
            revert("ERR-SL036 InvalidLockState");
        }
    }


    modifier paymentsLock() {
        // msg.sender is still the ExecutionEnvironment
        EscrowKey memory escrowKey = _escrowKey;

        console.log("payment lock A-0");

        require(escrowKey.isValidPaymentsLock(msg.sender), "ERR-SL037 InvalidLockStage");

        console.log("payment lock A-1");
        _escrowKey = escrowKey.holdPaymentsLock();
        _;

        console.log("payment lock A-2");
        if (escrowKey.callIndex == escrowKey.callMax-2) {
            _escrowKey = escrowKey.turnPaymentsLockRefund(msg.sender);
            console.log("payment lock A-2-0a");
        
        // Next searcher
        } else {
            _escrowKey = escrowKey.turnPaymentsLockSearcher(msg.sender);
            console.log("payment lock A-2-0b");
        }
        console.log("payment lock A-3");
    }

    modifier refundLock() {
        // msg.sender = ExecutionEnvironment
        console.log("refund lock A-0");
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidRefundLock(msg.sender), "ERR-SL038 InvalidLockStage");
        console.log("refund lock A-1");
        _;
       
        _escrowKey = escrowKey.turnRefundLock(msg.sender);
        console.log("refund lock A-2");
    }

    modifier verificationLock(uint16 callConfig) {
        // msg.sender = ExecutionEnvironment
        console.log("verification lock A-0");
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.isValidVerificationLock(msg.sender), "ERR-SL039 InvalidLockStage");

        console.log("verification lock A-1");

        if (callConfig.needsVerificationCall()) {
            console.log("verification lock A-1-0a");
            _escrowKey = escrowKey.holdVerificationLock();
            _; 

            console.log("verification lock A-1-1a");
            escrowKey = _escrowKey;
            require(escrowKey.confirmVerificationLock(), "ERR-SL040 LockInvalid");
            console.log("verification lock A-1-2a");
        }

        _escrowKey = escrowKey.turnVerificationLock(factory);
        console.log("verification lock A-2");
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