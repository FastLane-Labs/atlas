//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IAtlas } from "../interfaces/IAtlas.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ExecutionEnvironment } from "./ExecutionEnvironment.sol";
import { Metacall } from "./Metacall.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import { CallBits } from "../libraries/CallBits.sol";

contract UserDirect is Metacall, ExecutionEnvironment {
    using CallBits for uint16;

    constructor(
        address _user, 
        address _escrow, 
        address _factory,
        address _protocolControl,
        uint16 _callConfig
    ) ExecutionEnvironment(
        _user, 
        _escrow, 
        _factory,
        _protocolControl,
        _callConfig
    ) {
        if (!_callConfig.allowsRecycledStorage()) {
            // NOTE: selfdestruct will continue to work post EIP-6780 when it is triggered
            // in the same transaction as contract creation, which is what we do here.
            // selfdestruct(payable(_factory));
        }
    }

    function _validateProtocolControl(
        address userCallTo,
        uint256 searcherCallsLength,
        ProtocolCall calldata protocolCall,
        Verification calldata verification
    ) internal override returns (bool) {
        return IAtlas(factory).userDirectVerifyProtocol(
            msg.sender,
            userCallTo,
            searcherCallsLength,
            protocolCall,
            verification
        );
    }

    function _prepEnvironment(
        ProtocolCall calldata protocolCall
    ) internal override view returns (address environment) {
        require(protocolCall.to == control, "ERR-UD01 InvalidControl");
        require(protocolCall.callConfig == config, "ERR-UD02 InvalidConfig");
        environment = address(this);
    }

    function _execute(
        address,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] calldata payeeData, 
        SearcherCall[] calldata searcherCalls, 
        bytes32[] memory executionHashChain 
    ) internal override returns (CallChainProof memory) {
        return _protoCall(
            protocolCall,
            userCall,
            payeeData,
            searcherCalls,
            executionHashChain
        );
    }

    function _releaseLock(
        bytes32 key,
        ProtocolCall calldata protocolCall
    ) internal override {
        IAtlas(factory).userDirectReleaseLock(
            msg.sender,
            key,
            protocolCall
        );
    }

    function withdrawERC20(address token, uint256 amount) external {
        require(msg.sender == user, "ERR-EC01 NotEnvironmentOwner");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(
                ERC20(token), 
                msg.sender, 
                amount
            );

        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function factoryWithdrawERC20(address msgSender, address token, uint256 amount) external {
        require(msg.sender == factory, "ERR-EC10 NotFactory");
        require(msgSender == user, "ERR-EC11 NotEnvironmentOwner");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(
                ERC20(token), 
                user, 
                amount
            );

        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function withdrawEther(uint256 amount) external {
        require(msg.sender == user, "ERR-EC01 NotEnvironmentOwner");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(
                msg.sender, 
                amount
            );
            
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function factoryWithdrawEther(address msgSender, uint256 amount) external {
        require(msg.sender == factory, "ERR-EC10 NotFactory");
        require(msgSender == user, "ERR-EC11 NotEnvironmentOwner");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(
                user, 
                amount
            );
            
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }
}