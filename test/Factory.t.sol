// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { Factory } from "src/contracts/atlas/Factory.sol";
import { ExecutionEnvironment } from "src/contracts/common/ExecutionEnvironment.sol";
import { DummyDAppControl, CallConfigBuilder } from "./base/DummyDAppControl.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/UserOperation.sol";

import "./base/TestUtils.sol";

contract MockFactory is Factory, Test {
    constructor(address _executionTemplate) Factory(_executionTemplate) { }

    function getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        external
        returns (address executionEnvironment, DAppConfig memory dConfig)
    {
        return _getOrCreateExecutionEnvironment(userOp);
    }

    function computeSalt(address user, address control, uint32 callConfig) external view returns (bytes32) {
        return _computeSalt(user, control, callConfig);
    }

    function baseSalt() external view returns (bytes32) {
        return _FACTORY_BASE_SALT;
    }

    function getMimicCreationCode(
        address user,
        address control,
        uint32 callConfig
    )
        external
        view
        returns (bytes memory creationCode) {
            require(EXECUTION_ENV_TEMPLATE != address(0), "TEST: Execution environment template not set");
            return _getMimicCreationCode(user, control, callConfig);
        }
}

contract FactoryTest is Test {
    Atlas public atlas;
    AtlasVerification public atlasVerification;
    MockFactory public mockFactory;
    DummyDAppControl public dAppControl;

    address public user;

    function setUp() public {
        user = address(999);
        address deployer = address(333);
        address expectedAtlasAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 0);
        address expectedAtlasVerificationAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        address expectedFactoryAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedFactoryAddr));
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedFactoryAddr);
        
        vm.startPrank(deployer);
        atlas = new Atlas({
            escrowDuration: 64,
            verification: expectedAtlasVerificationAddr,
            simulator: address(0),
            executionTemplate: address(execEnvTemplate),
            initialSurchargeRecipient: deployer,
            l2GasCalculator: address(0)
        });
        assertEq(address(atlas), expectedAtlasAddr, "Atlas address mismatch");
        atlasVerification = new AtlasVerification(address(atlas));
        assertEq(address(atlasVerification), expectedAtlasVerificationAddr, "AtlasVerification address mismatch");
        mockFactory = new MockFactory({ _executionTemplate: address(execEnvTemplate) });
        assertEq(address(mockFactory), expectedFactoryAddr, "Factory address mismatch");
        dAppControl = new DummyDAppControl(expectedAtlasAddr, deployer, CallConfigBuilder.allFalseCallConfig());
        vm.stopPrank();
    }

    function test_createExecutionEnvironment() public {
        uint32 callConfig = dAppControl.CALL_CONFIG();
        bytes memory creationCode = mockFactory.getMimicCreationCode(user, address(dAppControl), callConfig);
        address expectedExecutionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(mockFactory),
                            mockFactory.computeSalt(user, address(dAppControl), callConfig),
                            keccak256(abi.encodePacked(creationCode))
                        )
                    )
                )
            )
        );

        assertTrue(expectedExecutionEnvironment.code.length == 0, "Execution environment should not exist");

        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit AtlasEvents.ExecutionEnvironmentCreated(user, expectedExecutionEnvironment);
        address actualExecutionEnvironment = mockFactory.createExecutionEnvironment(address(dAppControl), user);
        vm.stopPrank();

        assertFalse(actualExecutionEnvironment.code.length == 0, "Execution environment should exist");
        assertEq(
            expectedExecutionEnvironment, actualExecutionEnvironment, "Execution environment not the same as predicted"
        );
    }

    function test_getExecutionEnvironment() public {
        address executionEnvironment;
        bool exists;

        (executionEnvironment,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        assertFalse(exists, "Execution environment should not exist");
        assertTrue(executionEnvironment.codehash == bytes32(0), "Execution environment should not exist");

        vm.prank(user);
        mockFactory.createExecutionEnvironment(address(dAppControl), user);

        (executionEnvironment,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        assertTrue(exists, "Execution environment should exist");
        assertFalse(executionEnvironment.codehash == bytes32(0), "Execution environment should exist");
    }

    function test_getOrCreateExecutionEnvironment() public {
        UserOperation memory userOp;
        userOp.from = user;
        userOp.control = address(dAppControl);

        address predictedEE;
        address actualEE;
        bool exists;

        (predictedEE,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        assertFalse(exists, "Execution environment should not exist");
        assertTrue(predictedEE.code.length == 0, "Execution environment should not exist");

        // Actually deploy the EE
        (actualEE,) = mockFactory.getOrCreateExecutionEnvironment(userOp);
        assertEq(predictedEE, actualEE, "Predicted and actual EE addrs should match 2");

        (predictedEE,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        
        assertTrue(exists, "Execution environment should exist - exist should return true");
        assertFalse(predictedEE.code.length == 0, "Execution environment should exist - code at addr");
        assertEq(predictedEE, actualEE, "Predicted and actual EE addrs should match 2");
    }

    function test_factoryBaseAndComputedSalts() public view {
        bytes32 baseSalt = keccak256(abi.encodePacked(block.chainid, address(mockFactory)));
        assertEq(baseSalt, mockFactory.baseSalt(), "Factory base salt not set correctly");

        address _user = address(123);
        address _control = address(456);
        uint32 _callConfig = 789;

        bytes32 expectedComputeSalt = keccak256(abi.encodePacked(baseSalt, _user, _control, _callConfig));
        assertEq(expectedComputeSalt, mockFactory.computeSalt(_user, _control, _callConfig), "user salt not computed correctly - depends on base salt");
    }
}
