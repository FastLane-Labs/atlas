//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import { BitStuff } from "./BitStuff.sol"; 

import {
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    BidData,
    StagingCall,
    UserCall,
    CallConfig,
    EscrowKey,
    BaseLock,
    ExecutionPhase,
    SearcherSafety

} from "../libraries/DataTypes.sol";

contract SafetyChecks is BitStuff {

    address immutable public factory;

    EscrowKey internal _escrowKey;

    constructor(address factoryAddress) {
        factory = factoryAddress;
    }

    function searcherSafetyCallback() external payable returns (bool isSafe) {
        // an external call so that searcher contracts can verify
        // that delegatecall isn't being abused. 
        // NOTE: Protocol would still work fine if we removed this 
        // and let searchers handle the safety on their own.  There
        // are other ways to provide the same safety guarantees on
        // the contract level. This was chosen because it provides
        // excellent safety for beginning searchers while having
        // a minimal increase in gas cost compared with other options. 

        EscrowKey memory escrowKey = _escrowKey;

        isSafe = (
            escrowKey.approvedCaller == msg.sender &&
            _isLockDepth(BaseLock.Untrusted, escrowKey.lockState) &&
            _isExecutionPhase(ExecutionPhase.SearcherCalls, escrowKey.lockState) &&
            _isSafetyLevel(SearcherSafety.Requested, escrowKey.lockState)
        );
        
        if (isSafe) {
            // TODO: revert if bool fails?
            escrowKey.lockState = _updateSafetyLevel(
                SearcherSafety.Verified, SearcherSafety.Requested, escrowKey.lockState
           );
        } 

        _escrowKey = escrowKey;
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

        // set the total amount of searcher calls expected
        // NOTE: if the staging call is skipped, we will
        // decrement this call count at that time
        escrowKey.callMax = searcherCallCount + 2; 

        // set the next expected caller: the execution environment
        escrowKey.approvedCaller = executionEnvironment;

        // turn on the depth lock
        escrowKey.lockState = _updateLockDepth(
            BaseLock.Active, BaseLock.Unlocked, escrowKey.lockState
        );

        // set the next stage
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.Staging, ExecutionPhase.Uninitialized, escrowKey.lockState
        );

        _escrowKey = escrowKey;
    }

    function releaseEscrowLocks() external {
        EscrowKey memory escrowKey = _escrowKey;
        
        require(
            escrowKey.approvedCaller == msg.sender &&
            msg.sender == factory &&
            escrowKey.callIndex == escrowKey.callMax &&
            _isLockDepth(BaseLock.Pending, escrowKey.lockState) &&
            _isExecutionPhase(ExecutionPhase.Releasing, escrowKey.lockState),
            "ERR-ES001 NotUnlockable"
        );

        delete _escrowKey;
    }

    modifier stagingLock(uint16 callConfig) {

        EscrowKey memory escrowKey = _escrowKey;

        // safety contract needs to init all of the execution environment's
        // unsafe calls so that it can trust the locks.
        require(msg.sender == escrowKey.approvedCaller && msg.sender != address(0), "ERR-E31 InvalidCaller");
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(_isExecutionPhase(ExecutionPhase.Staging, escrowKey.lockState), "ERR-E32 AlreadyInitialized");
        require(escrowKey.callIndex == 0, "ERR-E34 InvalidIndex");

        // Handle staging calls, if needed
        if (_needsStaging(callConfig)) {
            
            // Handle the 
            if (_delegateStaging(callConfig)) {
                // update the lock depth, next caller, and then set the lock for searcher safety checks
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.DelegatingCall, BaseLock.Active, escrowKey.lockState
                );
                escrowKey.approvedCaller = address(0); // no approved escrow callers during staging
                
                _escrowKey = escrowKey;

                _;

                escrowKey = _escrowKey;

                // TODO: engage locks or not here, for first blank call?

                // Set the lock depth back 
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.Active, BaseLock.DelegatingCall, escrowKey.lockState
                );
                
            
            // handle regular call
            } else { 
                // update the lock phase and then set the lock for searcher safety checks
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.Untrusted, BaseLock.Active, escrowKey.lockState
                );
                escrowKey.approvedCaller = address(0); // no approved escrow callers during staging
                
                _escrowKey = escrowKey;

                _;

                escrowKey = _escrowKey;

                // Set the lock depth back
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.Active, BaseLock.Untrusted, escrowKey.lockState
                );
            }

            // set the approved caller back
            escrowKey.approvedCaller = msg.sender;
        }

        // prep for next step - UserCall - and store the lock
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.UserCall, ExecutionPhase.Staging, escrowKey.lockState
        );
        unchecked{ ++escrowKey.callIndex; }
        
        _escrowKey = escrowKey;
    }

    modifier userLock(uint16 callConfig) {

        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // calls so that it can trust the locks.
        require(
            msg.sender == escrowKey.approvedCaller && // approvedCaller = activeExecutionEnvironment
            msg.sender != address(0), 
            "ERR-E31 InvalidCaller"
        );
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(escrowKey.callIndex == 1, "ERR-E35 InvalidIndex");
        // prior stage was supposed to be "staging" but that could have been skipped.
        // Handle staging was NOT skipped
        require(
            _isExecutionPhase(ExecutionPhase.UserCall, escrowKey.lockState),
            "ERR-E35 InvalidStage"
        ); 

        bool isDelegateCall = _delegateUser(callConfig);

        // set the approved caller.  No approved caller during staging or user calls
        escrowKey.approvedCaller = address(0);
        
        // handle the user delegatecall case
        if (isDelegateCall) {
            // update the lock depth and then set the lock for searcher safety checks
            escrowKey.lockState = _updateLockDepth(
                BaseLock.DelegatingCall, BaseLock.Active, escrowKey.lockState
            );
            _escrowKey = escrowKey;

            _;

            escrowKey = _escrowKey;

            // Set the lock depth back
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Pending, BaseLock.DelegatingCall, escrowKey.lockState
            );
        
        // handle the user regular call case
        } else {
            // update the lock depth and then set the lock for searcher safety checks
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Untrusted, BaseLock.Active, escrowKey.lockState
            );
            _escrowKey = escrowKey;

            _;

            escrowKey = _escrowKey;

            // Set the lock depth back
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Pending, BaseLock.Untrusted, escrowKey.lockState
            );
        }

        // prep for next stage - searcher calls - and store the lock
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.SearcherCalls, ExecutionPhase.UserCall, escrowKey.lockState
        );
        escrowKey.approvedCaller = msg.sender;
        unchecked{ ++escrowKey.callIndex; }

        _escrowKey = escrowKey;
    }

    function _activateSearcherLock(
        address searcherTo
    ) internal {
        
        EscrowKey memory escrowKey = _escrowKey;

        // check, verify, and initialize the lock
        require(
            msg.sender == escrowKey.approvedCaller && 
            msg.sender != address(0), 
            "ERR-E31 InvalidCaller"
        ); // activeExecutionEnvironment

        // verify the stage
        if (escrowKey.callIndex == 2) {
            require(_isLockDepth(BaseLock.Pending, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        } else {
            require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        }
        require(_isExecutionPhase(ExecutionPhase.SearcherCalls, escrowKey.lockState), "ERR-E33 IncorrectStage");
        require(escrowKey.callIndex > 1 && escrowKey.callIndex < escrowKey.callMax, "ERR-E35 InvalidIndex");

        // set searcher's contract as approvedCaller for the searcher safety checks
        escrowKey.approvedCaller = searcherTo;

        // update the lock depth and store the key
        escrowKey.lockState = _updateLockDepth(
            BaseLock.Untrusted, BaseLock.Active, escrowKey.lockState
        );

        // verify and update the searcher safety requirement and store the escrowkey
        require(_isSafetyLevel(SearcherSafety.Unset, escrowKey.lockState), "ERR-E32 UnsafeLevel");
        escrowKey.lockState = _updateSafetyLevel(
            SearcherSafety.Requested, SearcherSafety.Unset, escrowKey.lockState
        );

        // Store the lock
        _escrowKey = escrowKey;
    }

    function _releaseSearcherLock(address searcherTo, bool makePayments) internal {
        // NOTE: Searcher should have performed the safety callback, 
        // which would have updated the SearcherSafety level in escrowKey

        // load the updated key
        EscrowKey memory escrowKey = _escrowKey;

        require(escrowKey.approvedCaller == searcherTo, "ERR-E60 CallerMismatch");
        require(escrowKey.approvedCaller != msg.sender, "ERR-E70 PossibleReentry");

        // verify and reset the searcher safety requirement and store the escrowkey
        require(_isSafetyLevel(SearcherSafety.Verified, escrowKey.lockState), "ERR-E32 UnsafeLevel");
        escrowKey.lockState = _updateSafetyLevel(
            SearcherSafety.Unset, SearcherSafety.Verified, escrowKey.lockState
        );

        // reset the approvedCaller back to the activeExecutionEnvironment
        escrowKey.approvedCaller = msg.sender;

        // set the lock depth back to active and store the escrowKey
        escrowKey.lockState = _updateLockDepth(
            BaseLock.Active, BaseLock.Untrusted, escrowKey.lockState
        );

        unchecked{ ++escrowKey.callIndex; } // Increment callIndex

        // Check if the call was successful and warrants payment processing
        if (makePayments) {
            require(!escrowKey.makingPayments, "ERR-E28 ImproperAccess");
            require(!escrowKey.paymentsComplete, "ERR-E29 AlreadyPaid");

            escrowKey.makingPayments = true;
            escrowKey.lockState = _updateExecutionPhase(
                ExecutionPhase.HandlingPayments, ExecutionPhase.SearcherCalls, escrowKey.lockState
            );
        

        // check if this is the final call - if so, prep for UserRefund
        // NOTE: if the payments handling preempts this conditional, 
        // we will set this flag at the end of the payment handling
        } else if (escrowKey.callIndex == escrowKey.callMax) {
            escrowKey.lockState = _updateExecutionPhase(
                ExecutionPhase.UserRefund, ExecutionPhase.SearcherCalls, escrowKey.lockState
            );
        }

        // store the lock
        _escrowKey = escrowKey;
    }

    modifier paymentsLock() {

        EscrowKey memory escrowKey = _escrowKey;

        // check, verify, and initialize the lock
        require(
            msg.sender == escrowKey.approvedCaller && 
            msg.sender != address(0), 
            "ERR-E31 InvalidCaller"
        ); // activeExecutionEnvironment

        require(escrowKey.makingPayments, "ERR-E28 ImproperAccess");
        require(!escrowKey.paymentsComplete, "ERR-E29 AlreadyPaid");
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(_isExecutionPhase(ExecutionPhase.HandlingPayments, escrowKey.lockState), "ERR-E33 IncorrectStage");
       
       // set searcher's contract as approvedCaller for the searcher safety checks
        escrowKey.approvedCaller = address(0);

        // update the lock depth and store the key
        escrowKey.lockState = _updateLockDepth(
            BaseLock.Untrusted, BaseLock.Active, escrowKey.lockState
        );

        _escrowKey = escrowKey;

        _;

        escrowKey = _escrowKey;

        // make sure we weren't bamboozled
        require(_isLockDepth(BaseLock.Untrusted, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(_isExecutionPhase(ExecutionPhase.HandlingPayments, escrowKey.lockState), "ERR-E33 IncorrectStage");

        escrowKey.makingPayments = false;
        escrowKey.paymentsComplete = true;

        escrowKey.lockState = _updateLockDepth(
            BaseLock.Active, BaseLock.Untrusted, escrowKey.lockState
        );

        // If this was the last searcher call, set execution phase to handle user refund next
        // otherwise, set it back to searcher calls. 
        if (escrowKey.callIndex == escrowKey.callMax) {
            escrowKey.lockState = _updateExecutionPhase(
                ExecutionPhase.UserRefund, ExecutionPhase.HandlingPayments, escrowKey.lockState
            );
        
        
        } else {
            escrowKey.lockState = _updateExecutionPhase(
                ExecutionPhase.SearcherCalls, ExecutionPhase.HandlingPayments, escrowKey.lockState
            );
        }

        // set approved caller back to the execution environment
        escrowKey.approvedCaller = msg.sender;

        // store the lock
        _escrowKey = escrowKey;
    }

    modifier refundLock() {

        EscrowKey memory escrowKey = _escrowKey;

        // check, verify, and initialize the lock
        require(
            msg.sender == escrowKey.approvedCaller && 
            msg.sender != address(0), 
            "ERR-E31 InvalidCaller"
        ); // activeExecutionEnvironment

        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(_isExecutionPhase(ExecutionPhase.UserRefund, escrowKey.lockState), "ERR-E33 IncorrectStage");
        require(escrowKey.callIndex == escrowKey.callMax && escrowKey.callIndex != 0, "ERR-E35 InvalidIndex");
        _;
        
        // Update the execution phase to enable the upcoming verification
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.Verification, ExecutionPhase.UserRefund, escrowKey.lockState
        );

        _escrowKey = escrowKey;
    }

    function handleVerification(
        StagingCall calldata stagingCall,
        bytes memory stagingData,
        bytes memory userReturnData
    ) external {

        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // calls so that it can trust the locks.
        require(msg.sender == escrowKey.approvedCaller, "ERR-E31 InvalidCaller");
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");

        // NOTE: the user gas refund will set the phase to Verification after it refunds
        require(_isExecutionPhase(ExecutionPhase.Verification, escrowKey.lockState), "ERR-E32 NotStaging");
        
        // we didn't know the verification calldata when creating the execution keys, but this is the final
        // call so we just make sure the call count is correct 
        require(escrowKey.callIndex == escrowKey.callMax, "ERR-E35 InvalidIndex");


        // if we don't verification, skip ahead and set lock depth to pending for release
        if (!_needsVerification(stagingCall.callConfig)) {
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Pending, BaseLock.Active, escrowKey.lockState
            );

        // handle verification case
        } else {
            
            // no approved callers during verification
            escrowKey.approvedCaller = address(0);

            // handle the verification delegatecall case
            if (_delegateVerification(stagingCall.callConfig)) {
                
                // Set the lock depth for searcher safety checks and store it
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.DelegatingCall, BaseLock.Active, escrowKey.lockState
                );
                _escrowKey = escrowKey;

                IExecutionEnvironment(
                    msg.sender
                ).delegateVerificationWrapper(
                    stagingCall,
                    stagingData,
                    userReturnData
                );

                // Set the lock depth to pending for final release
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.Pending, BaseLock.DelegatingCall, escrowKey.lockState
                );
            
            // handle the verification regular call case
            } else {

                // Set the lock depth for searcher safety checks and store it
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.Untrusted, BaseLock.Active, escrowKey.lockState
                );
                _escrowKey = escrowKey;

                IExecutionEnvironment(
                    msg.sender
                ).callVerificationWrapper(
                    stagingCall,
                    stagingData,
                    userReturnData
                );

                // Set the lock depth to pending for final release
                escrowKey.lockState = _updateLockDepth(
                    BaseLock.Pending, BaseLock.Untrusted, escrowKey.lockState
                );
            }
        }

        // set the next caller (the factory, finally), update the stage, and store it.
        escrowKey.approvedCaller = factory;
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.Releasing, ExecutionPhase.Verification, escrowKey.lockState
        );
        _escrowKey = escrowKey;
    }

      //////////////////////////////////
     //////////// BIT MATH ////////////
    //////////////////////////////////

    // storage
    function _setLockDepth(BaseLock newDepth, BaseLock oldDepth) internal {
        _escrowKey.lockState ^= uint64(
            (1 << uint64(newDepth)) | 
            (1 << uint64(oldDepth))
        );
    } 

    function _setExecutionPhase(ExecutionPhase newStage, ExecutionPhase oldStage) internal {
        _escrowKey.lockState ^= uint64(
            (1 << _EXECUTION_PHASE_OFFSET + uint64(newStage)) | 
            (1 << _EXECUTION_PHASE_OFFSET + uint64(oldStage))
        );
    }

    function _setSafetyLevel(SearcherSafety newLevel, SearcherSafety oldLevel) internal {
        _escrowKey.lockState ^= uint64(
            (1 << _SAFETY_LEVEL_OFFSET + uint64(newLevel)) | 
            (1 << _SAFETY_LEVEL_OFFSET + uint64(oldLevel))
        );
    }

}