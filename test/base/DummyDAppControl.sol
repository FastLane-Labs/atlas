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
    bool public preOpsShouldRevert;
    bool public userOpShouldRevert;
    bool public preSolverShouldRevert;
    bool public postSolverShouldRevert;
    bool public allocateValueShouldRevert;
    bool public postOpsShouldRevert;

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

    function _checkUserOperation(UserOperation memory) internal pure virtual override { }

    function _preOpsCall(UserOperation calldata userOp) internal virtual override returns (bytes memory) {
        if (userOp.data.length == 0) {
            return new bytes(0);
        }

        (bool success, bytes memory data) = address(userOp.dapp).call(userOp.data);
        require(success, "_preOpsCall reverted");
        return data;
    }

    function _postOpsCall(bool, bytes calldata data) internal pure virtual override {
        if (data.length == 0) return;

        (bool shouldRevert) = abi.decode(data, (bool));
        require(!shouldRevert, "_postOpsCall revert requested");
    }

    function _preSolverCall(SolverOperation calldata, bytes calldata returnData) internal view virtual override {
        if (returnData.length == 0) {
            return;
        }

        (bool shouldRevert) = abi.decode(returnData, (bool));
        require(!shouldRevert, "_preSolverCall revert requested");
    }

    function _postSolverCall(SolverOperation calldata, bytes calldata returnData) internal pure virtual override {
        if (returnData.length == 0) {
            return;
        }

        (bool shouldRevert) = abi.decode(returnData, (bool));
        require(!shouldRevert, "_postSolverCall revert requested");
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

        bool shouldRevert = DummyDAppControl(CONTROL).allocateValueShouldRevert();
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

    // Revert settings

    function setPreOpsShouldRevert(bool _preOpsShouldRevert) public {
        preOpsShouldRevert = _preOpsShouldRevert;
    }

    function setUserOpShouldRevert(bool _userOpShouldRevert) public {
        userOpShouldRevert = _userOpShouldRevert;
    }

    function setPreSolverShouldRevert(bool _preSolverShouldRevert) public {
        preSolverShouldRevert = _preSolverShouldRevert;
    }

    function setPostSolverShouldRevert(bool _postSolverShouldRevert) public {
        postSolverShouldRevert = _postSolverShouldRevert;
    }

    function setAllocateValueShouldRevert(bool _allocateValueShouldRevert) public {
        allocateValueShouldRevert = _allocateValueShouldRevert;
    }

    function setPostOpsShouldRevert(bool _postOpsShouldRevert) public {
        postOpsShouldRevert = _postOpsShouldRevert;
    }
}
