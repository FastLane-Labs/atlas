//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import { CallVerification } from "../libraries/CallVerification.sol";

import {
    BidData,
    PayeeData,
    PaymentData,
    UserCall,
    CallChainProof
} from "../libraries/DataTypes.sol";

library ExecutionControl {
    using CallVerification for CallChainProof;

    // NOTE: By requiring the staging and verification calls
    // to be either static (no state modifications) or delegated
    // (only modify state of caller's contract - the FastLane Execution
    // Environment), ProtocolControl can be confident that the state on 
    // their own contracts won't be modified by the users unless it is
    // explicitly allowed, such as by building in their own callback
    // that the delegatecall function then accesses. 

    function stage(
        CallChainProof memory proof,
        address protocolControl,
        UserCall calldata userCall
    ) internal returns (bytes memory) {

        bool isDelegated = IProtocolControl(protocolControl).stagingDelegated();

        bytes memory data = abi.encodeWithSelector(
            IProtocolControl.stageCall.selector, 
            userCall
        );

        // Verify the proof to ensure this isn't happening out of sequence.
        require(
            proof.prove(protocolControl, data, isDelegated),
            "ERR-P01 ProofInvalid"
        );

        if (isDelegated) {
            return delegateWrapper(
                protocolControl,
                data
            );
        
        } else {
            return staticWrapper(
                protocolControl,
                data
            );
        }
    }

    function user(
        CallChainProof memory proof,
        address protocolControl,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) internal returns (bytes memory) {

        (bool delegated, bool local) = IProtocolControl(protocolControl).userDelegatedLocal();

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
                    protocolControl,
                    abi.encodeWithSelector(IProtocolControl.userLocalCall.selector,
                        userCall.to, 
                        userCall.value, 
                        stagingReturnData, 
                        userCall.data
                    )
                );
            
            } else {
                return staticWrapper(
                    protocolControl,
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
        address protocolControl,
        uint256 totalEtherReward,
        BidData[] memory bids,
        PayeeData[] calldata payeeData
    ) internal {

        if (IProtocolControl(protocolControl).allocatingDelegated()) {
            delegateWrapper(
                protocolControl,
                abi.encodeWithSelector(
                    IProtocolControl.allocatingCall.selector,
                    totalEtherReward,
                    bids,
                    payeeData
                )
            );
        
        } else {
            callWrapper(
                protocolControl,
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
        address protocolControl,
        bytes memory stagingReturnData,
        bytes memory userReturnData
    ) internal returns (bool) {

        bool isDelegated = IProtocolControl(protocolControl).verificationDelegated();

        bytes memory data = abi.encodeWithSelector(
            IProtocolControl.verificationCall.selector, 
            stagingReturnData,
            userReturnData
        );

        // Verify the proof to ensure this isn't happening out of sequence.
        require(
            proof.prove(protocolControl, data, isDelegated),
            "ERR-P01 ProofInvalid"
        );
        if (isDelegated) {
            return abi.decode(
                delegateWrapper(
                    protocolControl,
                    data
                ),
                (bool)
            );
        
        } else {
            return abi.decode(
                staticWrapper(
                    protocolControl,
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
        require(success, "ERR-EC01 DelegateRevert");
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
        require(success, "ERR-EC02 StaticRevert");
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
        require(success, "ERR-EC03a CallRevert");
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
        require(success, "ERR-EC03b CallRevert");
        return returnData;
    }
}