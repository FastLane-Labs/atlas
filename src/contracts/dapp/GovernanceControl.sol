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
    // Virtual functions to be overridden by participating dApp governance
    // (not FastLane) prior to deploying contract. Note that dApp governance
    // will "own" this contract but that it should be immutable.

    /////////////////////////////////////////////////////////
    //                  PRE OPS                            //
    /////////////////////////////////////////////////////////
    //
    // PreOps:
    // Data should be decoded as:
    //
    //     bytes calldata userOpData
    //

    // _preOpsCall
    // Details:
    //  preOps/delegate =
    //      Inputs: User's calldata
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // DApp exposure: Trustless
    // User exposure: Trustless
    function _preOpsCall(UserCall calldata uCall)
        internal
        virtual
        returns (bytes memory);


    /////////////////////////////////////////////////////////
    //                  USER                               //
    /////////////////////////////////////////////////////////
    //
    // Data should be decoded as:
    //
    //    bytes calldata userOpData
    //
    // NOTE: preOpsReturnData is the returned data from the preOps transaction

    // _userLocalDelegateCall
    // Details:
    //  user/local/delegate =
    //      Inputs: User's calldata + preOps call's returnData
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) to the ExecutionEnvironment
    //
    // DApp exposure: Trustless
    // User exposure: Trustless
    // NOTE: To mitigate the risk of exploit, this is disabled if ProtococolControl has enabled
    // "recycled storage."  The Trustless assumptions are only as good as the underlying smart contract,
    // and there's no way for FastLane to certify that DAppControl isn't accidentally accessing
    // dirty / malicious storage from previous calls. User would be exposed to high smart contract risk,
    // otherwise.
    function _userLocalDelegateCall(bytes calldata) internal virtual returns (bytes memory) {
        revert(_NOT_IMPLEMENTED);
    }

    // _userLocalStandardCall
    // Details:
    //  user/local/standard =
    //      Inputs: User's calldata + preOps call's returnData
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the DAppControl contract
    //      Access: Storage access (read+WRITE) to the DAppControl contract
    //
    // DApp exposure: Trustless, but high risk of contract exploit by malicious user
    // User exposure: Trustless
    // NOTE: There is a timelock on governance's ability to change the DAppControl contract
    // NOTE: Allowing this is ill-advised unless your reentry / locking system is flawless.
    function _userLocalStandardCall(bytes calldata) internal virtual returns (bytes memory) {
        revert(_NOT_IMPLEMENTED);
    }

    /////////////////////////////////////////////////////////
    //                MEV ALLOCATION                       //
    /////////////////////////////////////////////////////////
    //
    // _allocateValueCall
    // Details:
    //  allocate/delegate =
    //      Inputs: MEV Profits (ERC20 balances) 
    //      Function: Executing the function set by DAppControl / MEVAllocator
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // DApp exposure: Trustless
    // User exposure: Trustless
    function _allocateValueCall(bytes calldata data) internal virtual;

    /////////////////////////////////////////////////////////
    //              INTENT FULFILLMENT                     //
    /////////////////////////////////////////////////////////
    //

    // _preSolverCall
    //
    // Details:
    //  Data should be decoded as:
    //
    //    address solverTo, bytes memory returnData
    //
    //  fulfillment(preOps)/delegatecall =
    //      Inputs: preOps call's returnData, winning solver to address
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    //      NOTE: This happens *inside* of the solver's try/catch wrapper
    //      and is designed to give the solver everything they need to fulfill
    //      the user's 'intent.'

    function _preSolverCall(bytes calldata) internal virtual returns (bool) {
        revert(_NOT_IMPLEMENTED);
    }


    // _postSolverCall
    //
    // Details:
    //
    //  Data should be decoded as:
    //
    //    address solverTo, bytes memory returnData
    //

    //  fulfillment(verification)/delegatecall =
    //      Inputs: preOps call's returnData, winning solver to address
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    //      NOTE: This happens *inside* of the solver's try/catch wrapper
    //      and is designed to make sure that the solver is fulfilling
    //      the user's 'intent.'

    function _postSolverCall(bytes calldata) internal virtual returns (bool) {
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

    // _postOpsCall
    // Details:
    //  verification/delegatecall =
    //      Inputs: User's return data + preOps call's returnData
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    function _postOpsCall(bytes calldata) internal virtual returns (bool) {
        revert(_NOT_IMPLEMENTED);
    }

    /////////////////////////////////////////////////////////
    //                 GETTERS & HELPERS                   //
    /////////////////////////////////////////////////////////
    //
    // View functions used by the backend to verify bid format
    // and by the factory and DAppVerification to verify the
    // backend.
    function _validateUserOperation(UserCall calldata) internal view virtual returns (bool) {
        return true;
    }

    function getPayeeData(bytes calldata data) external view virtual returns (PayeeData[] memory);

    function getBidFormat(UserCall calldata uCall) external view virtual returns (BidData[] memory);

    function getBidValue(SolverOperation calldata solverOp) external view virtual returns (uint256);
}
