// //SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.16;

// import {IDAppControl} from "../interfaces/IDAppControl.sol";
// import {Escrow} from "./Escrow.sol";

// import {Mimic} from "./Mimic.sol";
// import {ExecutionEnvironment} from "./ExecutionEnvironment.sol";

// import "../types/SolverCallTypes.sol";
// import "../types/UserCallTypes.sol";
// import "../types/DAppApprovalTypes.sol";

// import {CallBits} from "../libraries/CallBits.sol";

// contract Factory is Escrow {
//     //address immutable public atlas;
//     using CallBits for uint32;

//     bytes32 public immutable salt;
//     address public immutable executionTemplate;

//     constructor(uint32 _escrowDuration, address _simulator) Escrow(_escrowDuration, _simulator) {
//         //atlas = msg.sender;
//         salt = keccak256(abi.encodePacked(block.chainid, atlas, "Atlas 1.0"));

//         executionTemplate = _deployExecutionEnvironmentTemplate(
//             address(this), DAppConfig({to: address(0), callConfig: uint32(0), bidToken: address(0)})
//         );
//     }

//     // GETTERS
//     function getEscrowAddress() external view returns (address escrowAddress) {
//         escrowAddress = atlas;
//     }

//     function execution() external view returns (address) {
//         return executionTemplate;
//     }

//     function createExecutionEnvironment(address dAppControl) external returns (address executionEnvironment) {
//         executionEnvironment = _setExecutionEnvironment(dAppControl, msg.sender, dAppControl.codehash);
//         _initializeNonce(msg.sender);
//     }

//     function getExecutionEnvironment(address user, address dAppControl)
//         external
//         view
//         returns (address executionEnvironment, uint32 callConfig, bool exists)
//     {
//         callConfig = IDAppControl(dAppControl).callConfig();
//         executionEnvironment = _getExecutionEnvironmentCustom(user, dAppControl.codehash, dAppControl, callConfig);
//         exists = executionEnvironment.codehash != bytes32(0);
//     }

//     function _getExecutionEnvironment(address user, bytes32 controlCodeHash, address controller)
//         internal
//         view
//         returns (address executionEnvironment)
//     {
//         uint32 callConfig = IDAppControl(controller).callConfig();

//         executionEnvironment = _getExecutionEnvironmentCustom(user, controlCodeHash, controller, callConfig);
//     }

//     // NOTE: This func is used to generate the address of user ExecutionEnvironments that have
//     // been deprecated due to DAppControl changes of callConfig.
//     function _getExecutionEnvironmentCustom(
//         address user,
//         bytes32 controlCodeHash,
//         address controller,
//         uint32 callConfig
//     ) internal view returns (address executionEnvironment) {
//         executionEnvironment = address(
//             uint160(
//                 uint256(
//                     keccak256(
//                         abi.encodePacked(
//                             bytes1(0xff),
//                             address(this),
//                             salt,
//                             keccak256(
//                                 abi.encodePacked(_getMimicCreationCode(controller, callConfig, user, controlCodeHash))
//                             )
//                         )
//                     )
//                 )
//             )
//         );
//     }

//     function _setExecutionEnvironment(address dAppControl, address user, bytes32 controlCodeHash)
//         internal
//         returns (address executionEnvironment)
//     {
//         uint32 callConfig = IDAppControl(dAppControl).callConfig();

//         bytes memory creationCode = _getMimicCreationCode(dAppControl, callConfig, user, controlCodeHash);

//         executionEnvironment = address(
//             uint160(
//                 uint256(
//                     keccak256(
//                         abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(abi.encodePacked(creationCode)))
//                     )
//                 )
//             )
//         );

//         if (executionEnvironment.codehash == bytes32(0)) {
//             bytes32 memSalt = salt;
//             assembly {
//                 executionEnvironment := create2(0, add(creationCode, 32), mload(creationCode), memSalt)
//             }

//             emit NewExecutionEnvironment(executionEnvironment, user, dAppControl, callConfig);
//         }
//     }

//     function _deployExecutionEnvironmentTemplate(address, DAppConfig memory)
//         internal
//         returns (address executionEnvironment)
//     {
//         ExecutionEnvironment _environment = new ExecutionEnvironment{
//             salt: salt
//         }(atlas);

//         executionEnvironment = address(_environment);
//     }

//     /*
//     add(
//                                 shl(96, executionLib), 
//                                 0xFFFFFFFFFFFFFFFFFFFFFFFFF
//                 )
//             )
//             */

//     function _getMimicCreationCode(address controller, uint32 callConfig, address user, bytes32 controlCodeHash)
//         internal
//         view
//         returns (bytes memory creationCode)
//     {
//         address executionLib = executionTemplate;
//         // NOTE: Changing compiler settings or solidity versions can break this.
//         creationCode = type(Mimic).creationCode;

//         // TODO: unpack the SHL and reorient 
//         assembly {
//             mstore(
//                 add(creationCode, 85), 
//                 or(
//                     and(
//                         mload(add(creationCode, 85)),
//                         not(shl(96, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
//                     ),
//                     shl(96, executionLib)
//                 )
//             )           
            
//             mstore(
//                 add(creationCode, 118), 
//                 or(
//                     and(
//                         mload(add(creationCode, 118)),
//                         not(shl(96, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
//                     ),
//                     shl(96, user)
//                 )
//             )    
            
//             mstore(
//                 add(creationCode, 139),
//                 or(
//                     and(
//                         mload(add(creationCode, 139)),
//                         not(shl(56, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFF))
//                     ),
//                     add(shl(96, controller), add(shl(88, 0x63), shl(56, callConfig)))
//                 )
//             )

//             mstore(add(creationCode, 165), controlCodeHash)
//         }
//     }

//     function getMimicCreationCode(address controller, uint32 callConfig, address user, bytes32 controlCodeHash)
//         external
//         view
//         returns (bytes memory creationCode)
//     {
//         creationCode = _getMimicCreationCode(controller, callConfig, user, controlCodeHash);
//     }
// }
