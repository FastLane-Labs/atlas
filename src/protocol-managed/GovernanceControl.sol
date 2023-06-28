//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";

import {
    BidData,
    PayeeData
} from "../libraries/DataTypes.sol";

abstract contract GovernanceControl {

    string internal constant NOT_IMPLEMENTED = "NOT IMPLEMENTED";
    // Virtual functions to be overridden by participating protocol governance 
    // (not FastLane) prior to deploying contract. Note that protocol governance
    // will "own" this contract but that it should be immutable.  

      /////////////////////////////////////////////////////////
     //                  STAGING                            //
    /////////////////////////////////////////////////////////
    //
    // Staging: 
    // Data should be decoded as:
    //
    //     bytes calldata userCallData
    //

    // _stageDelegateCall
    // Details:
    //  staging/delegate = 
    //      Inputs: User's calldata 
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // Protocol exposure: Trustless 
    // User exposure: Trustless 
    function _stageDelegateCall(
        bytes calldata data
    ) internal virtual returns (bytes memory stagingData);

    // _stageStaticCall
    // Details:
    //  staging/static = 
    //      Inputs: User's calldata 
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the ProtocolControl contract
    //      Access: With storage access (read only) to the ProtocolControl
    //
    // Protocol exposure: Trustless 
    // User exposure: Trustless 
    function _stageStaticCall(
        bytes calldata
    ) internal view virtual returns (bytes memory) {
        revert(NOT_IMPLEMENTED);
    }



      /////////////////////////////////////////////////////////
     //                  USER                               //
    /////////////////////////////////////////////////////////
    //
    // Data should be decoded as:
    //
    //    address userCallTo,
    //    uint256 userCallValue,
    //    bytes memory stagingReturnData,
    //    bytes memory userCallData
    //
    // NOTE: stagingReturnData is the returned data from the staging transaction
    
    // _userLocalDelegateCall
    // Details:
    //  user/local/delegate = 
    //      Inputs: User's calldata + staging call's returnData
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) to the ExecutionEnvironment
    //
    // Protocol exposure: Trustless 
    // User exposure: Trustless
    // NOTE: To mitigate the risk of exploit, this is disabled if ProtococolControl has enabled 
    // "recycled storage."  The Trustless assumptions are only as good as the underlying smart contract,
    // and there's no way for FastLane to certify that ProtocolControl isn't accidentally accessing
    // dirty / malicious storage from previous calls. User would be exposed to high smart contract risk,
    // otherwise. 
    function _userLocalDelegateCall(
        bytes memory
    ) internal virtual returns (bytes memory) {
        revert(NOT_IMPLEMENTED);
    }

    // _userLocalStandardCall
    // Details:
    //  user/local/standard = 
    //      Inputs: User's calldata + staging call's returnData
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the ProtocolControl contract
    //      Access: Storage access (read+WRITE) to the ProtocolControl contract
    //
    // Protocol exposure: Trustless, but high risk of contract exploit by malicious user
    // User exposure: Trustless
    // NOTE: There is a timelock on governance's ability to change the ProtocolControl contract
    // NOTE: Allowing this is ill-advised unless your reentry / locking system is flawless.
    function _userLocalStandardCall(
        bytes memory
    ) internal virtual returns (bytes memory) {
        revert(NOT_IMPLEMENTED);
    }
    
      /////////////////////////////////////////////////////////
     //                  VERIFICATION                       //
    /////////////////////////////////////////////////////////
    //
    // Data should be decoded as:
    //
    //    bytes memory stagingReturnData,
    //    bytes memory userReturnData
    //

    // _verificationDelegateCall
    // Details:
    //  verification/delegatecall = 
    //      Inputs: User's return data + staging call's returnData
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    function _verificationDelegateCall(
        bytes calldata
    ) internal virtual returns (bool) {
        revert(NOT_IMPLEMENTED); 
    }

    // _verificationStaticCall
    // Details:
    //  verification/delegatecall = 
    //      Inputs: User's return data + staging call's returnData
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the ProtocolControl contract
    //      Access: Storage access (read only) to the ProtocolControl contract
    function _verificationStaticCall(
        bytes calldata
    ) internal view virtual returns (bool) {
        revert(NOT_IMPLEMENTED);
    }


      /////////////////////////////////////////////////////////
     //                 GETTERS & HELPERS                   //
    /////////////////////////////////////////////////////////
    //
    // View functions used by the backend to verify bid format
    // and by the factory and ProtocolVerifier to verify the
    // backend.  

    function getPayeeData(bytes calldata data) 
        external virtual 
        returns (PayeeData[] memory);
    
    function getBidFormat(bytes calldata data) 
        external virtual
        returns (BidData[] memory);
}