//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

import "forge-std/Test.sol";

abstract contract GovernanceControl {

    address internal immutable _executionBase;

    constructor () {
        _executionBase = address(this);
    }

    string internal constant _NOT_IMPLEMENTED = "NOT IMPLEMENTED";
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

    // _stagingCall
    // Details:
    //  staging/delegate =
    //      Inputs: User's calldata
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // Protocol exposure: Trustless
    // User exposure: Trustless
    function _stagingCall(UserMetaTx calldata userMetaTx)
        internal
        virtual
        returns (bytes memory);


    /////////////////////////////////////////////////////////
    //                  USER                               //
    /////////////////////////////////////////////////////////
    //
    // Data should be decoded as:
    //
    //    bytes calldata userCallData
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
    function _userLocalDelegateCall(bytes calldata) internal virtual returns (bytes memory) {
        revert(_NOT_IMPLEMENTED);
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
    function _userLocalStandardCall(bytes calldata) internal virtual returns (bytes memory) {
        revert(_NOT_IMPLEMENTED);
    }

    /////////////////////////////////////////////////////////
    //                MEV ALLOCATION                       //
    /////////////////////////////////////////////////////////
    //
    // _allocatingCall
    // Details:
    //  allocate/delegate =
    //      Inputs: MEV Profits (ERC20 balances) 
    //      Function: Executing the function set by ProtocolControl / MEVAllocator
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // Protocol exposure: Trustless
    // User exposure: Trustless
    function _allocatingCall(bytes calldata data) internal virtual;

    /////////////////////////////////////////////////////////
    //              INTENT FULFILLMENT                     //
    /////////////////////////////////////////////////////////
    //

    // _searcherPreCall
    //
    // Details:
    //  Data should be decoded as:
    //
    //    address searcherTo, bytes memory returnData
    //
    //  fulfillment(staging)/delegatecall =
    //      Inputs: staging call's returnData, winning searcher to address
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    //      NOTE: This happens *inside* of the searcher's try/catch wrapper
    //      and is designed to give the searcher everything they need to fulfill
    //      the user's 'intent.'

    function _searcherPreCall(bytes calldata) internal virtual returns (bool) {
        revert(_NOT_IMPLEMENTED);
    }


    // _searcherPostCall
    //
    // Details:
    //
    //  Data should be decoded as:
    //
    //    address searcherTo, bytes memory returnData
    //

    //  fulfillment(verification)/delegatecall =
    //      Inputs: staging call's returnData, winning searcher to address
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    //      NOTE: This happens *inside* of the searcher's try/catch wrapper
    //      and is designed to make sure that the searcher is fulfilling
    //      the user's 'intent.'

    function _searcherPostCall(bytes calldata) internal virtual returns (bool) {
        revert(_NOT_IMPLEMENTED);
    }

    /////////////////////////////////////////////////////////
    //                  VERIFICATION                       //
    /////////////////////////////////////////////////////////
    //
    // Data should be decoded as:
    //
    //    bytes memory returnData
    //

    // _verificationCall
    // Details:
    //  verification/delegatecall =
    //      Inputs: User's return data + staging call's returnData
    //      Function: Executing the function set by ProtocolControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    function _verificationCall(bytes calldata) internal virtual returns (bool) {
        revert(_NOT_IMPLEMENTED);
    }

    /////////////////////////////////////////////////////////
    //                 GETTERS & HELPERS                   //
    /////////////////////////////////////////////////////////
    //
    // View functions used by the backend to verify bid format
    // and by the factory and ProtocolVerifier to verify the
    // backend.
    function _validateUserCall(UserMetaTx calldata) internal view virtual returns (bool) {
        return true;
    }

    function getPayeeData(bytes calldata data) external view virtual returns (PayeeData[] memory);

    function getBidFormat(UserMetaTx calldata userMetaTx) external view virtual returns (BidData[] memory);

    function getBidValue(SearcherCall calldata searcherCall) external view virtual returns (uint256);
}
