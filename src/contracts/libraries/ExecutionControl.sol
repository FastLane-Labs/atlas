//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import { CallBits } from "../libraries/CallBits.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import "forge-std/Test.sol";
contract ExecutionControl is Test {
//library ExecutionControl {
    using CallVerification for CallChainProof;
    using CallBits for uint16;

    // NOTE: By requiring the staging and verification calls
    // to be either static (no state modifications) or delegated
    // (only modify state of caller's contract - the FastLane Execution
    // Environment), ProtocolControl can be confident that the state on 
    // their own contracts won't be modified by the users unless it is
    // explicitly allowed, such as by building in their own callback
    // that the delegatecall function then accesses. 

    function stage(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) internal returns (bytes memory) {

        bool isDelegated = protocolCall.callConfig.needsDelegateStaging();
        
        bytes memory stagingCalldata = abi.encode(
            userCall.to, 
            userCall.from,
            bytes4(userCall.data), 
            userCall.data[4:]
        );

        // Verify the proof to ensure this isn't happening out of sequence.
        require(
            proof.prove(protocolCall.to, stagingCalldata, isDelegated),
            "ERR-P01 ProofInvalid"
        );

        console.log("protocolCall.to",protocolCall.to);

        if (isDelegated) {
            return delegateWrapper(
                protocolCall.to,
                abi.encodeWithSelector(
                    IProtocolControl.stageCall.selector, 
                    stagingCalldata
                )
            );
        
        } else {
            return staticWrapper(
                protocolCall.to,
                abi.encodeWithSelector(
                    IProtocolControl.stageCall.selector, 
                    stagingCalldata
                )
            );
        }
    }

    function user(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) internal returns (bytes memory) {

        bool delegated = protocolCall.callConfig.needsDelegateUser();
        bool local = protocolCall.callConfig.needsLocalUser();

        // Verify the proof to ensure this isn't happening out of sequence. 
        require(
            proof.prove(userCall.to, userCall.data, delegated),
            "ERR-P01 ProofInvalid"
        );

        // regular user call - executed at regular destination and not performed locally
        if (!local) {
            return userCallWrapper(
                userCall.to,
                userCall.value,
                userCall.data
            );
        
        } else {
            if (delegated) {
                return delegateWrapper(
                    protocolCall.to,
                    abi.encodeWithSelector(IProtocolControl.userLocalCall.selector,
                        userCall.to, 
                        userCall.value, 
                        stagingReturnData, 
                        userCall.data
                    )
                );
            
            } else {
                return staticWrapper(
                    protocolCall.to,
                    abi.encodeWithSelector(
                        IProtocolControl.userLocalCall.selector,
                        userCall.to, 
                        userCall.value, 
                        stagingReturnData, 
                        userCall.data
                    )
                );
            }
        }
    }

    function allocate(
        ProtocolCall calldata protocolCall,
        uint256 totalEtherReward,
        BidData[] memory bids,
        PayeeData[] calldata payeeData
    ) internal {

        if (protocolCall.callConfig.needsDelegateAllocating()) {
             delegateWrapper(
                protocolCall.to,
                abi.encodeWithSelector(
                    IProtocolControl.allocatingCall.selector,
                    totalEtherReward,
                    bids,
                    payeeData
                )
            );
        
        } else {
            callWrapper(
                protocolCall.to,
                totalEtherReward,
                abi.encodeWithSelector(
                    IProtocolControl.allocatingCall.selector,
                    totalEtherReward,
                    bids,
                    payeeData
                )
            );
        }
    }

    function verify(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData,
        bytes memory userReturnData
    ) internal returns (bool) {

        bool isDelegated = protocolCall.callConfig.needsDelegateVerification();

        bytes memory data = abi.encodeWithSelector(
            IProtocolControl.verificationCall.selector, 
            stagingReturnData,
            userReturnData
        );

        // Verify the proof to ensure this isn't happening out of sequence.
        require(
            proof.prove(protocolCall.to, data, isDelegated),
            "ERR-P01 ProofInvalid"
        );
        if (isDelegated) {
            return abi.decode(
                delegateWrapper(
                    protocolCall.to,
                    data
                ),
                (bool)
            );
        
        } else {
            return abi.decode(
                staticWrapper(
                    protocolCall.to,
                    data
                ),
                (bool)
            );
        }
    }

    // TODO: make calldata-accepting versions of these to save gas
    function delegateWrapper(
        address protocolControl,
        bytes memory data
    ) internal returns (bytes memory) 
    {
        (bool success, bytes memory returnData) = protocolControl.delegatecall(
            data
        );
        require(success, "ERR-EC02 DelegateRevert");
        return returnData;
    }

    function staticWrapper(
        address protocolControl,
        bytes memory data
    ) internal view returns (bytes memory) 
    {
        (bool success, bytes memory returnData) = protocolControl.staticcall(
            data
        );
        require(success, "ERR-EC03 StaticRevert");
        return returnData;
    }

    function userCallWrapper(
        address to,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) 
    {
        (bool success, bytes memory returnData) = to.call{
            value: value
        }(
            data
        );
        require(success, "ERR-EC04a CallRevert");
        return returnData;
    }

    function callWrapper(
        address to,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) 
    {
        (bool success, bytes memory returnData) = to.call{
            value: value
        }(
            data
        );
        require(success, "ERR-EC04b CallRevert");
        return returnData;
    }
}