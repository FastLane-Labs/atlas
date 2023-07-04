//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";
import { ICallExecution } from "../interfaces/ICallExecution.sol";

import { Escrow } from "./Escrow.sol";
import { UserDirect } from "./UserDirect.sol";

import "../types/CallTypes.sol";

contract Factory {

    uint32 immutable public escrowDuration;
    address immutable public escrow;
    address immutable public factory;
    bytes32 immutable public salt;

    Escrow public escrowContract = new Escrow(uint32(64));

    mapping(address => bytes32) public environments;

    constructor(
            uint32 _escrowDuration
    ) {
        escrowDuration = _escrowDuration;

        escrow = address(escrowContract);
        factory = address(this);
        salt = keccak256(
            abi.encodePacked(
                block.chainid,
                factory,
                escrow
            )
        );
    }

    // USER TOKEN WITHDRAWAL FUNCS
    function withdrawERC20(address token, uint256 amount, ProtocolCall memory protocolCall) external {
       
        if (protocolCall.callConfig == uint16(0)) {
            protocolCall = IProtocolControl(protocolCall.to).getProtocolCall();
        }

        ICallExecution(
            _getExecutionEnvironmentCustom(msg.sender, protocolCall)
        ).factoryWithdrawERC20(msg.sender, token, amount);
    }

    function withdrawEther(uint256 amount, ProtocolCall memory protocolCall) external {
        if (protocolCall.callConfig == uint16(0)) {
            protocolCall = IProtocolControl(protocolCall.to).getProtocolCall();
        }

        ICallExecution(
            _getExecutionEnvironmentCustom(msg.sender, protocolCall)
        ).factoryWithdrawEther(msg.sender, amount);
    }

    // GETTERS
    function getExecutionEnvironment(
        address user,
        address protocolControl
    ) external view returns (
        address executionEnvironment
    ) {
        executionEnvironment = _getExecutionEnvironment(user, protocolControl);
    }

    function getEscrowAddress() external view returns (address escrowAddress) {
        escrowAddress = escrow;
    }

    function _getExecutionEnvironment(
        address user,
        address protocolControl
    ) internal view returns (
        address executionEnvironment
    ) { 
        ProtocolCall memory protocolCall = IProtocolControl(protocolControl).getProtocolCall();
        return _getExecutionEnvironmentCustom(user, protocolCall);
    }

    // NOTE: This func is used to generate the address of user ExecutionEnvironments that have 
    // been deprecated due to ProtocolControl changes of callConfig. 
    function _getExecutionEnvironmentCustom(
        address user,
        ProtocolCall memory protocolCall
    ) internal view returns (
        address environment
    ) {

        address protocolControl = protocolCall.to;
        uint16 callConfig = protocolCall.callConfig;

        environment = address(uint160(uint256(
            keccak256(abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                    abi.encodePacked(
                        type(UserDirect).creationCode,
                        abi.encode(
                            user,
                            escrow,
                            address(this),
                            protocolControl,
                            callConfig
                        )
                    )
                )
            )
        )))); 
    }

    function _deployExecutionEnvironment(
        address user,
        ProtocolCall memory protocolCall
    ) internal returns (
        address environment
    ) {
        address protocolControl = protocolCall.to;
        uint16 callConfig = protocolCall.callConfig;

        UserDirect _environment = new UserDirect{
            salt: salt
        }(
            user, 
            escrow,
            address(this),
            protocolControl,
            callConfig
        );

        environment = address(_environment);

        environments[environment] = keccak256(abi.encodePacked(
            user,
            protocolControl,
            callConfig
        ));
    }
} 