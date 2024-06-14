// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

import "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";

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

    function _preOpsCall(UserOperation calldata userOp) internal virtual override returns (bytes memory) {
        if (userOp.data.length == 0) {
            return new bytes(0);
        }

        (bool success, bytes memory data) = address(userOp.dapp).call(userOp.data);
        require(success, "_preOpsCall reverted");
        return data;
    }

    function _postOpsCall(bool, bytes calldata data) internal pure virtual override returns (bool) {
        if (data.length == 0) {
            return true;
        }

        (bool shouldRevert) = abi.decode(data, (bool));
        require(!shouldRevert, "_postOpsCall revert requested");
        return true;
    }

    function _preSolverCall(SolverOperation calldata, bytes calldata returnData) internal pure virtual override {
        if (returnData.length == 0) {
            return;
        }

        (bool shouldRevert, bool returnValue) = abi.decode(returnData, (bool, bool));
        require(!shouldRevert, "_preSolverCall revert requested");
        if (!returnValue) revert("_preSolverCall returned false");
    }

    function _postSolverCall(SolverOperation calldata, bytes calldata returnData) internal pure virtual override {
        if (returnData.length == 0) {
            return;
        }

        (bool shouldRevert, bool returnValue) = abi.decode(returnData, (bool, bool));
        require(!shouldRevert, "_postSolverCall revert requested");
        if (!returnValue) revert("_postSolverCall returned false");
    }

    function _allocateValueCall(
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
        require(!shouldRevert, "_allocateValueCall revert requested");
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
