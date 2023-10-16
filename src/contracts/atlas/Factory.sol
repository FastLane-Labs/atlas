//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Escrow} from "./Escrow.sol";
import {IDAppControl} from "../interfaces/IDAppControl.sol";

import {Mimic} from "./Mimic.sol";
import {ExecutionEnvironment} from "./ExecutionEnvironment.sol";
import {Permit69} from "../common/Permit69.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

contract Factory is Test, Escrow, Permit69 {
    //address immutable public atlas;
    using CallBits for uint32;
    bytes32 public immutable salt;
    address public immutable execution;

    constructor(uint32 _escrowDuration, address _simulator) Escrow(_escrowDuration, _simulator) {
        //atlas = msg.sender;
        salt = keccak256(abi.encodePacked(block.chainid, atlas, "Atlas 1.0"));

        execution =
            _deployExecutionEnvironmentTemplate(address(this), DAppConfig({to: address(0), callConfig: uint32(0)}));
    }

    // GETTERS
    function environment() public view override returns (address _environment) {
        _environment = activeEnvironment;
    }

    function getEscrowAddress() external view returns (address escrowAddress) {
        escrowAddress = atlas;
    }

    function getExecutionEnvironment(UserOperation calldata userOp, address controller)
        external
        view
        returns (address executionEnvironment)
    {
        executionEnvironment = _getExecutionEnvironment(userOp.call.from, controller.codehash, controller);
    }

    function _getExecutionEnvironment(address user, bytes32 controlCodeHash, address controller)
        internal
        view
        returns (address executionEnvironment)
    {
        DAppConfig memory dConfig = IDAppControl(controller).getDAppConfig();
        
        executionEnvironment = _getExecutionEnvironmentCustom(user, controlCodeHash, dConfig.to, dConfig.callConfig);
    }

    // NOTE: This func is used to generate the address of user ExecutionEnvironments that have
    // been deprecated due to DAppControl changes of callConfig.
    function _getExecutionEnvironmentCustom(address user, bytes32 controlCodeHash, address controller, uint32 callConfig)
        internal
        view
        override
        returns (address executionEnvironment)
    {
        
        /*
        if (controlCodeHash == bytes32(0)) {
            controlCodeHash = controller.codehash;
        }

        if (callConfig == 0) {
            callConfig = CallBits.buildCallConfig(controller);
        }
        */
        
        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    _getMimicCreationCode(
                                        controller, callConfig, execution, user, controlCodeHash
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    function _setExecutionEnvironment(DAppConfig calldata dConfig, address user, bytes32 controlCodeHash)
        internal
        returns (address executionEnvironment)
    {
        bytes memory creationCode =
            _getMimicCreationCode(dConfig.to, dConfig.callConfig, execution, user, controlCodeHash);

        executionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(abi.encodePacked(creationCode))
                        )
                    )
                )
            )
        );

        if (executionEnvironment.codehash == bytes32(0)) {
            bytes32 memSalt = salt;
            assembly {
                executionEnvironment := create2(0, add(creationCode, 32), mload(creationCode), memSalt)
            }

            emit NewExecutionEnvironment(executionEnvironment, user, dConfig.to, dConfig.callConfig);
        }
    }

    function _deployExecutionEnvironmentTemplate(address, DAppConfig memory) internal returns (address executionEnvironment) {
        ExecutionEnvironment _environment = new ExecutionEnvironment{
            salt: salt
        }(atlas);

        executionEnvironment = address(_environment);
    }

    function _getMimicCreationCode(
        address controller,
        uint32 callConfig,
        address executionLib,
        address user,
        bytes32 controlCodeHash
    ) internal pure returns (bytes memory creationCode) {
        // NOTE: Changing compiler settings or solidity versions can break this.
        creationCode = type(Mimic).creationCode;
        assembly {
            mstore(add(creationCode, 85), add(shl(96, executionLib), 0x73ffffffffffffffffffffff))
            mstore(add(creationCode, 131), add(shl(96, user), 0x73ffffffffffffffffffffff))
            mstore(
                add(creationCode, 152),
                add(
                    shl(96, controller), 
                    add(
                        add(
                            shl(88, 0x63), 
                            shl(56, callConfig)
                        ), 
                        0x7f000000000000
                    )
                )
            )
            mstore(add(creationCode, 178), controlCodeHash)
        }
    }
}
