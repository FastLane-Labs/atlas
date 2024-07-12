// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

import "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";

import "forge-std/Test.sol";

library CallConfigBuilder {
    function allFalseCallConfig() internal pure returns (CallConfig memory) { }
}

contract DummyDAppControl is DAppControl {
    event MEVPaymentSuccess(address bidToken, uint256 bidAmount);

    constructor(
        address _atlas,
        address _governance,
        CallConfig memory _callConfig
    )
        DAppControl(_atlas, _governance, _callConfig)
    { }

    // ****************************************
    // Atlas overrides
    // ****************************************

    function _preOpsDelegateCall(UserOperation calldata userOp) internal virtual override returns (bytes memory) {
        if (userOp.data.length == 0) {
            return new bytes(0);
        }

        (bool success, bytes memory data) = address(userOp.dapp).call(userOp.data);
        require(success, "_preOpsDelegateCall reverted");
        return data;
    }

    function _postOpsDelegateCall(bool, bytes calldata data) internal pure virtual override {
        if (data.length == 0) return;

        (bool shouldRevert) = abi.decode(data, (bool));
        require(!shouldRevert, "_postOpsDelegateCall revert requested");
    }

    function _preSolverDelegateCall(
        SolverOperation calldata,
        bytes calldata returnData
    )
        internal
        view
        virtual
        override
    {
        if (returnData.length == 0) {
            return;
        }

        (bool shouldRevert) = abi.decode(returnData, (bool));
        require(!shouldRevert, "_preSolverDelegateCall revert requested");
    }

    function _postSolverDelegateCall(
        SolverOperation calldata,
        bytes calldata returnData
    )
        internal
        pure
        virtual
        override
    {
        if (returnData.length == 0) {
            return;
        }

        (bool shouldRevert) = abi.decode(returnData, (bool));
        require(!shouldRevert, "_postSolverDelegateCall revert requested");
    }

    function _allocateValueDelegateCall(
        address bidToken,
        uint256 winningAmount,
        bytes calldata data
    )
        internal
        virtual
        override
    {
        if (data.length == 0) {
            return;
        }

        (bool shouldRevert) = abi.decode(data, (bool));
        require(!shouldRevert, "_allocateValueDelegateCall revert requested");
        emit MEVPaymentSuccess(bidToken, winningAmount);
    }

    function getBidValue(SolverOperation calldata solverOp) public view virtual override returns (uint256) {
        return solverOp.bidAmount;
    }

    function getBidFormat(UserOperation calldata) public view virtual override returns (address) { }

    // ****************************************
    // Custom functions
    // ****************************************

    function userOperationCall(bool shouldRevert, uint256 returnValue) public pure returns (uint256) {
        require(!shouldRevert, "userOperationCall revert requested");
        return returnValue;
    }
}
