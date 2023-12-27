// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DAppControl } from "../../src/contracts/dapp/DAppControl.sol";

import "../../src/contracts/types/DAppApprovalTypes.sol";
import "../../src/contracts/types/UserCallTypes.sol";
import "../../src/contracts/types/SolverCallTypes.sol";

library CallConfigBuilder {
    function allFalseCallConfig() internal pure returns (CallConfig memory) { }
}

contract DummyDAppControl is DAppControl {
    constructor(
        address escrow,
        address governance,
        CallConfig memory _callConfig
    )
        DAppControl(escrow, governance, _callConfig)
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

        (bool shouldRevert, bool returnValue) = abi.decode(data, (bool, bool));
        require(!shouldRevert, "_postSolverCall revert requested");
        return returnValue;
    }

    function _preSolverCall(bytes calldata data) internal pure virtual override returns (bool) {
        if (data.length == 0) {
            return true;
        }

        (,, bytes memory dAppReturnData) = abi.decode(data, (address, uint256, bytes));
        (bool shouldRevert, bool returnValue) = abi.decode(dAppReturnData, (bool, bool));
        require(!shouldRevert, "_preSolverCall revert requested");
        return returnValue;
    }

    function _postSolverCall(bytes calldata data) internal pure virtual override returns (bool) {
        if (data.length == 0) {
            return true;
        }

        (,, bytes memory dAppReturnData) = abi.decode(data, (address, uint256, bytes));
        (bool shouldRevert, bool returnValue) = abi.decode(dAppReturnData, (bool, bool));
        require(!shouldRevert, "_postSolverCall revert requested");
        return returnValue;
    }

    function _allocateValueCall(address, uint256, bytes calldata data) internal virtual override {
        if (data.length == 0) {
            return;
        }

        (bool shouldRevert) = abi.decode(data, (bool));
        require(!shouldRevert, "_allocateValueCall revert requested");
    }

    function getBidFormat(UserOperation calldata) public view virtual override returns (address) { }
    function getBidValue(SolverOperation calldata) public view virtual override returns (uint256) { }

    // ****************************************
    // Custom functions
    // ****************************************

    function userOperationCall(bool shouldRevert, uint256 returnValue) public pure returns (uint256) {
        require(!shouldRevert, "userOperationCall revert requested");
        return returnValue;
    }
}
