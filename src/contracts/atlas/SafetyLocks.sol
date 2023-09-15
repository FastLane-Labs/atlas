//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafetyBits} from "../libraries/SafetyBits.sol";
import {CallBits} from "../libraries/CallBits.sol";

import {ProtocolCall, UserMetaTx} from "../types/CallTypes.sol";
import "../types/LockTypes.sol";

import "forge-std/Test.sol";

contract SafetyLocks is Test {
    using SafetyBits for EscrowKey;
    using CallBits for uint16;

    address public immutable atlas;

    address internal constant UNLOCKED = address(1);

    address public activeEnvironment = UNLOCKED;

    constructor() {
        atlas = address(this);
    }

    function searcherSafetyCallback(address msgSender) external payable returns (bool isSafe) {
        // An external call so that searcher contracts can verify
        // that delegatecall isn't being abused.

        isSafe = msgSender == activeEnvironment;
    }

    function _initializeEscrowLock(address executionEnvironment) onlyWhenUnlocked internal {

        activeEnvironment = executionEnvironment;
    }

    function _buildEscrowLock(
        ProtocolCall calldata protocolCall,
        address executionEnvironment,
        uint8 searcherCallCount
    ) internal view returns (EscrowKey memory self) {

        require(activeEnvironment == executionEnvironment, "ERR-SL004 NotInitialized");

        self = self.initializeEscrowLock(
            protocolCall.callConfig.needsStagingCall(), searcherCallCount, executionEnvironment
        );
    }

    function _releaseEscrowLock() internal {
        activeEnvironment = UNLOCKED;
    }

    modifier onlyWhenUnlocked() {
        require(activeEnvironment == UNLOCKED, "ERR-SL003 AlreadyInitialized");
        _;
    }
}
