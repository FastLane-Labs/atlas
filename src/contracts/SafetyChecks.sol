//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISafetyChecks } from "../interfaces/ISafetyChecks.sol";
import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";

import {
    SearcherOutcome,
    SearcherCall,
    SearcherMetaTx,
    BidData,
    StagingCall,
    UserCall,
    CallConfig
} from "../libraries/DataTypes.sol";

contract SafetyChecks is ISafetyChecks {

    uint64 constant internal _EXECUTION_PHASE_OFFSET = uint64(type(BaseLock).max);
    uint64 constant internal _SAFETY_LEVEL_OFFSET = uint64(type(BaseLock).max) + uint64(type(ExecutionPhase).max);

    uint256 immutable public chainId;
    address immutable public factory;

    EscrowKey internal _escrowKey;
    bytes32 internal _executionHash;

    constructor(address factoryAddress) {
        chainId = block.chainid;
        factory = factoryAddress;
    }

    /*
    function searcherSafetyCall(
        address searcherFrom, // the searcherCall.metaTx.from
        address executionCaller // the address of the ExecutionEnvironment 
        // NOTE: the execution caller is the msg.sender to the searcher's contract
    ) external returns (bool isSafe) {

        EscrowKey memory escrowKey = _escrowKey;

        // an external call so that searcher contracts can verify
        // that delegatecall isn't being abused. This MUST be used
        // by every searcher contract!
        isSafe = (
            //!escrowKey.isDelegatingCall &&
            escrowKey.executionPhase == uint8(ExecutionPhase.SearcherCalls) &&
            escrowKey.pendingKey == keccak256(abi.encodePacked(
                searcherSender,
                msg.sender,
                executionCaller,
                1 << uint8(ExecutionPhase.SearcherCalls)
            )) &&
            escrowKey.approvedCaller == executionCaller &&
            escrowKey.searcherSafety == uint8(SearcherSafety.Requested)
        );
        
        if (isSafe) {
            // TODO: revert if bool fails?
            escrowKey.searcherSafety = uint8(SearcherSafety.Verified);
        }

        _escrowKey = escrowKey;
    }
    */

    function initializeEscrowLocks(
        address executionEnvironment,
        uint8 searcherCallCount
    ) external {
        
        EscrowKey memory escrowKey = _escrowKey;
        
        require(
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
        delete _executionHash;
    }

    function handleStaging(
        bytes32 targetHash,
        StagingCall calldata stagingCall,
        bytes calldata userCallData
    ) external returns (bytes memory stagingData) {

        EscrowKey memory escrowKey = _escrowKey;

        // safety contract needs to init all of the execution environment's
        // unsafe calls so that it can trust the locks.
        require(msg.sender == escrowKey.approvedCaller && msg.sender != address(0), "ERR-E31 InvalidCaller");
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(_isExecutionPhase(ExecutionPhase.Staging, escrowKey.lockState), "ERR-E32 AlreadyInitialized");

        bool isDelegateCall = _delegateStaging(stagingCall.callConfig);

        // verify the calldata and sequence
        require(
            _validateCall(
                targetHash,
                isDelegateCall,
                escrowKey.callIndex++, // increment the call index
                bytes.concat(stagingCall.stagingSelector, userCallData)
            ),
            "ERR-E34 InvalidCallKey" 
        );
        
        // handle delegatecall
        if (isDelegateCall) {
            // update the lock depth, next caller, and then set the lock for searcher safety checks
            escrowKey.lockState = _updateLockDepth(
                BaseLock.DelegatingCall, BaseLock.Active, escrowKey.lockState
            );
            escrowKey.approvedCaller = address(0); // no approved escrow callers during staging
            _escrowKey = escrowKey;

            // call the callback
            stagingData = IExecutionEnvironment(
                msg.sender
            ).delegateStagingWrapper(
                stagingCall,
                userCallData
            );

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

            // call the callback
            stagingData = IExecutionEnvironment(
                payable(msg.sender) // NOTE: msg.value might be different from userCall.value
            ).callStagingWrapper(
                stagingCall,
                userCallData
            );

            // Set the lock depth back
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Active, BaseLock.Untrusted, escrowKey.lockState
            );
        }

        // prep for next step - UserCall - and store the lock
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.UserCall, ExecutionPhase.Staging, escrowKey.lockState
        );
        escrowKey.approvedCaller = msg.sender;
        _escrowKey = escrowKey;
    }

    function handleUser(
        bytes32 targetHash,
        uint16 callConfig,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData) {

        EscrowKey memory escrowKey = _escrowKey;

        // Safety contract needs to init all of the execution environment's
        // calls so that it can trust the locks.
        require(
            msg.sender == escrowKey.approvedCaller && // approvedCaller = activeExecutionEnvironment
            msg.sender != address(0), 
            "ERR-E31 InvalidCaller"
        );
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        
        // prior stage was supposed to be "staging" but that could have been skipped.
        // Handle staging was NOT skipped
        if (_isExecutionPhase(ExecutionPhase.UserCall, escrowKey.lockState)) {
            require(escrowKey.callIndex == 1, "ERR-E35 InvalidIndex");

        // Handle staging was skipped
        } else if (_isExecutionPhase(ExecutionPhase.Staging, escrowKey.lockState)) {
            require(escrowKey.callIndex == 0, "ERR-E35 InvalidIndex");
            escrowKey.lockState = _updateExecutionPhase(
                ExecutionPhase.UserCall, ExecutionPhase.Staging, escrowKey.lockState
            );

            // NOTE: Since the staging call was skipped, decrement the max calls we expect
            escrowKey.callMax -= 1;

        } else {
            revert("ERR-E32 IncorrectStage");
        } 

        bool isDelegateCall = _delegateUser(callConfig);

        // verify the calldata and sequence
        require(
            _validateCall(
                targetHash,
                isDelegateCall,
                escrowKey.callIndex++, // post increment the call index
                userCall.data
            ),
            "ERR-E34 InvalidCallKey" 
        );

        // set the approved caller.  No approved caller during staging or user calls
        escrowKey.approvedCaller = address(0);
        
        // handle the user delegatecall case
        if (isDelegateCall) {
            // update the lock depth and then set the lock for searcher safety checks
            escrowKey.lockState = _updateLockDepth(
                BaseLock.DelegatingCall, BaseLock.Active, escrowKey.lockState
            );
            _escrowKey = escrowKey;

            userReturnData = IExecutionEnvironment(
                msg.sender
            ).delegateUserWrapper(
                userCall
            );

            // Set the lock depth back
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Active, BaseLock.DelegatingCall, escrowKey.lockState
            );
        
        // handle the user regular call case
        } else {
            // update the lock depth and then set the lock for searcher safety checks
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Untrusted, BaseLock.Active, escrowKey.lockState
            );
            _escrowKey = escrowKey;

            userReturnData = IExecutionEnvironment(
                msg.sender // NOTE: uses the userCall.value for setting, balance is held on execution environment
            ).callUserWrapper(
                userCall
            );

            // Set the lock depth back
            escrowKey.lockState = _updateLockDepth(
                BaseLock.Active, BaseLock.Untrusted, escrowKey.lockState
            );
        }

        // prep for next stage - searcher calls - and store the lock
        escrowKey.lockState = _updateExecutionPhase(
            ExecutionPhase.SearcherCalls, ExecutionPhase.UserCall, escrowKey.lockState
        );
        escrowKey.approvedCaller = msg.sender;
        _escrowKey = escrowKey;
    }

    modifier openSearcherLock(
        bytes32 targetHash,
        address searcherTo,
        bytes calldata searcherCallData
    ) {
        
        EscrowKey memory escrowKey = _escrowKey;

        // check, verify, and initialize the lock
        require(
            msg.sender == escrowKey.approvedCaller && 
            msg.sender != address(0), 
            "ERR-E31 InvalidCaller"
        ); // activeExecutionEnvironment

        // verify the stage
        require(_isLockDepth(BaseLock.Active, escrowKey.lockState), "ERR-E30 InvalidLockDepth");
        require(_isExecutionPhase(ExecutionPhase.SearcherCalls, escrowKey.lockState), "ERR-E33 IncorrectStage");
        

        // verify the calldata and sequence
        require(
            _validateCall(
                targetHash,
                false,
                escrowKey.callIndex++, // post increment callIndex for next searcher
                searcherCallData
            ),
            "ERR-E34 InvalidCallKey" 
        );

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
        _escrowKey = escrowKey;

        // do the call
        _;
    }

    modifier closeSearcherLock() {
        // NOTE: Searcher should have performed the safety callback, 
        // which would have updated the SearcherSafety level in escrowKey

        _;
        // load the updated key
        EscrowKey memory escrowKey = _escrowKey;

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

        // check if this was a success prompts a payment handling call
        if (escrowKey.makingPayments) {
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

    function _validateCall(
        bytes32 targetHash,
        bool isDelegateCall,
        uint256 index,
        bytes memory executedData
    ) internal returns (bool) {
        bytes32 newExecutionHash = keccak256(
            abi.encodePacked(
                _executionHash,
                executedData,
                isDelegateCall,
                index
            )
        );
        
        if (targetHash == newExecutionHash) {
            _executionHash = newExecutionHash;
            return true;

        } else {
            return false;
        }
    }

    //////////// BIT MATH ////////////

    function _delegateStaging(uint16 callConfig) internal pure returns (bool delegateStaging) {
        delegateStaging = (callConfig & 1 << uint16(CallConfig.DelegateStaging) != 0);
    }

    function _delegateUser(uint16 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = (callConfig & 1 << uint16(CallConfig.DelegateUser) != 0);
    }

    function _delegateVerification(uint16 callConfig) internal pure returns (bool delegateVerification) {
        delegateVerification = (callConfig & 1 << uint16(CallConfig.DelegateStaging) != 0);
    }

    function _needsStaging(uint16 callConfig) internal pure returns (bool needsStaging) {
        needsStaging = (callConfig & 1 << uint16(CallConfig.CallStaging) != 0);
    }

    function _fwdValueStaging(uint16 callConfig) internal pure returns (bool fwdValueStaging) {
        fwdValueStaging = (callConfig & 1 << uint16(CallConfig.FwdValueStaging) != 0);
    }

    function _needsVerification(uint16 callConfig) internal pure returns (bool needsVerification) {
        needsVerification = (callConfig & 1 << uint16(CallConfig.CallStaging) != 0);
    }

    // NOTE: Order of bits for LockState:
    // Lowest bits = BaseLock
    // Middle bits = Execution Phase
    // Highest bits = SearcherSafety

    function _isAtOrBelowLockDepth(BaseLock depth, uint64 lockState) internal pure returns (bool) {
        // BaseLock is the first few bits in the lockState
        return !((lockState & ~(uint64(1) << (uint64(depth)+1))) != 0);
    }

    function _isLockDepth(BaseLock depth, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << uint64(depth)) != 0;
    }

    // storage
    function _setLockDepth(BaseLock newDepth, BaseLock oldDepth) internal {
        _escrowKey.lockState ^= uint64(
            (1 << uint64(newDepth)) | 
            (1 << uint64(oldDepth))
        );
    }

    // memory
    function _updateLockDepth(
        BaseLock newDepth, 
        BaseLock oldDepth,
        uint64 lockState
    ) internal pure returns (uint64) {
        lockState ^= uint64(
            (1 << uint64(newDepth)) | 
            (1 << uint64(oldDepth))
        );
        return lockState;
    }

    function _isExecutionPhase(ExecutionPhase stage, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << (_EXECUTION_PHASE_OFFSET + uint64(stage))) != 0;
    }

    // storage
    function _setExecutionPhase(ExecutionPhase newStage, ExecutionPhase oldStage) internal {
        _escrowKey.lockState ^= uint64(
            (1 << _EXECUTION_PHASE_OFFSET + uint64(newStage)) | 
            (1 << _EXECUTION_PHASE_OFFSET + uint64(oldStage))
        );
    }

    // memory
    function _updateExecutionPhase(
        ExecutionPhase newStage, 
        ExecutionPhase oldStage,
        uint64 lockState
    ) internal pure returns (uint64) {
        lockState ^= uint64(
            (1 << _EXECUTION_PHASE_OFFSET + uint64(newStage)) | 
            (1 << _EXECUTION_PHASE_OFFSET + uint64(oldStage))
        );
        return lockState;
    }

    function _isSafetyLevel(SearcherSafety safetyLevel, uint64 lockState) internal pure returns (bool) {
        return (lockState & 1 << (_SAFETY_LEVEL_OFFSET + uint64(safetyLevel))) != 0;
    }

    // storage
    function _setSafetyLevel(SearcherSafety newLevel, SearcherSafety oldLevel) internal {
        _escrowKey.lockState ^= uint64(
            (1 << _SAFETY_LEVEL_OFFSET + uint64(newLevel)) | 
            (1 << _SAFETY_LEVEL_OFFSET + uint64(oldLevel))
        );
    }

    // memory
    function _updateSafetyLevel(
        SearcherSafety newLevel, 
        SearcherSafety oldLevel,
        uint64 lockState
    ) internal pure returns (uint64) {
        lockState ^= uint64(
            (1 << _SAFETY_LEVEL_OFFSET + uint64(newLevel)) | 
            (1 << _SAFETY_LEVEL_OFFSET + uint64(oldLevel))
        );
        return lockState;
    }



}