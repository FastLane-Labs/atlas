//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IExecutionEnvironment } from "../interfaces/IExecutionEnvironment.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";

import { Factory } from "./Factory.sol";
import { ProtocolVerifier } from "./ProtocolVerification.sol";
import { Metacall } from "./Metacall.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract Atlas is Test, Metacall, Factory, ProtocolVerifier {

    bytes32 internal _userLock;

    constructor(
        address _fastlanePayee,
        uint32 _escrowDuration
    ) Factory(_escrowDuration) {}

    function _validateProtocolControl(
        address environment,
        address userCallTo,
        uint256 searcherCallsLength,
        ProtocolCall calldata protocolCall,
        Verification calldata verification
    ) internal override returns (bool) {
        if (!_verifyProtocol(userCallTo, protocolCall, verification)) {
            return false;
        }

        // Initialize the escrow locks
        ISafetyLocks(escrow).initializeEscrowLocks(
            environment,
            uint8(searcherCallsLength)
        );

        console.log("locked for", environment);

        return true;
    }

    function _prepEnvironment(ProtocolCall calldata protocolCall) internal override returns (address environment) {
        // Calculate the user's execution environment address
        environment = _getExecutionEnvironment(msg.sender, protocolCall.to);

        // Initialize a new, blank execution environment for the user if there isn't one already
        if (environment.codehash == bytes32(0)) {
            environment = _deployExecutionEnvironment(
                msg.sender,
                protocolCall
            );
        }
    }

    function _execute(
        address environment,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, 
        SearcherCall[] calldata searcherCalls, 
        bytes32[] memory executionHashChain 
    ) internal override returns (CallChainProof memory) {
        return IExecutionEnvironment(environment).protoCall(
            protocolCall,
            userCall,
            payeeData,
            searcherCalls,
            executionHashChain
        );
    }

    function _releaseLock(bytes32, ProtocolCall calldata) internal override {
        ISafetyLocks(escrow).releaseEscrowLocks();
    }

    function userDirectVerifyProtocol(
        address userCallFrom,
        address userCallTo,
        uint256 searcherCallsLength,
        ProtocolCall calldata protocolCall,
        Verification calldata verification
    ) external returns (bool invalidCall) {
        require(
            environments[msg.sender] == keccak256(
                abi.encodePacked(
                    userCallFrom,
                    protocolCall.to,
                    protocolCall.callConfig
                )
            ), 
            "ERR-H03 InvalidCaller"
        );
        // require(userCallFrom == tx.origin, "ERR-H04 InvalidCaller"); // DISABLE FOR FORGE TESTING
        require(_userLock == bytes32(0), "ERR-H05 AlreadyLocked");
        
        if (!_verifyProtocol(userCallTo, protocolCall, verification)) {
            return false;
        }

        // Initialize the escrow locks
        ISafetyLocks(escrow).initializeEscrowLocks(
            address(msg.sender),
            uint8(searcherCallsLength)
        );

        // Store the penultimate call hash
        _userLock = verification.proof.callChainHash;

        return true;
    }

    function userDirectReleaseLock(
        address userCallFrom,
        bytes32 key,
        ProtocolCall calldata protocolCall
    ) external {

        require(
            environments[msg.sender] == keccak256(
                abi.encodePacked(
                    userCallFrom,
                    protocolCall.to,
                    protocolCall.callConfig
                )
            ), 
            "ERR-H03 InvalidCaller"
        );
        // require(userCallFrom == tx.origin, "ERR-H04 InvalidCaller"); // DISABLE FOR FORGE TESTING
        require(key == _userLock && key != bytes32(0), "ERR-H05 IncorrectKey");
        
        delete _userLock;

        ISafetyLocks(escrow).releaseEscrowLocks();
    }
}