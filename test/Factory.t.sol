// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import { Factory } from "src/contracts/atlas/Factory.sol";
import { ExecutionEnvironment } from "src/contracts/atlas/ExecutionEnvironment.sol";
import { DummyDAppControl, CallConfigBuilder } from "./base/DummyDAppControl.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import "src/contracts/types/UserCallTypes.sol";

import "./base/TestUtils.sol";

contract MockFactory is Factory, Test {
    constructor(address _executionTemplate) Factory(_executionTemplate) { }

    function getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        external
        returns (address executionEnvironment, DAppConfig memory dConfig)
    {
        return _getOrCreateExecutionEnvironment(userOp);
    }

    function salt() external returns (bytes32) {
        return _salt;
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
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, expectedFactoryAddr, "AtlasFactory 1.0"));
        ExecutionEnvironment execEnvTemplate = new ExecutionEnvironment{ salt: salt }(expectedFactoryAddr);
        
        vm.startPrank(deployer);
        atlas = new Atlas({
            _escrowDuration: 64,
            _verification: expectedAtlasVerificationAddr,
            _simulator: address(0),
            _executionTemplate: address(execEnvTemplate),
            _surchargeRecipient: deployer
        });
        assertEq(address(atlas), expectedAtlasAddr, "Atlas address mismatch");
        atlasVerification = new AtlasVerification(address(atlas));
        assertEq(address(atlasVerification), expectedAtlasVerificationAddr, "AtlasVerification address mismatch");
        mockFactory = new MockFactory({ _executionTemplate: address(execEnvTemplate) });
        assertEq(address(mockFactory), expectedFactoryAddr, "Factory address mismatch");
        dAppControl = new DummyDAppControl(expectedAtlasAddr, deployer, CallConfigBuilder.allFalseCallConfig());
        vm.stopPrank();
        
        console.log("Factory address: ", address(mockFactory));
        console.log("Factory expected address: ", expectedFactoryAddr);
    }

    function test_createExecutionEnvironment() public {
        uint32 callConfig = dAppControl.CALL_CONFIG();
        bytes memory creationCode = TestUtils._getMimicCreationCode(
            address(dAppControl), callConfig, mockFactory.executionTemplate(), user, address(dAppControl).codehash
        );
        address expectedExecutionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(mockFactory),
                            mockFactory.salt(),
                            keccak256(abi.encodePacked(creationCode))
                        )
                    )
                )
            )
        );

        assertTrue(expectedExecutionEnvironment.codehash == bytes32(0), "Execution environment should not exist");

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit AtlasEvents.ExecutionEnvironmentCreated(user, expectedExecutionEnvironment);
        address actualExecutionEnvironment = mockFactory.createExecutionEnvironment(address(dAppControl));

        assertFalse(expectedExecutionEnvironment.codehash == bytes32(0), "Execution environment should exist");
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
        mockFactory.createExecutionEnvironment(address(dAppControl));

        (executionEnvironment,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        assertTrue(exists, "Execution environment should exist");
        assertFalse(executionEnvironment.codehash == bytes32(0), "Execution environment should exist");
    }

    function test_getOrCreateExecutionEnvironment() public {
        UserOperation memory userOp;
        userOp.from = user;
        userOp.control = address(dAppControl);

        address executionEnvironment;
        bool exists;

        (executionEnvironment,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        assertFalse(exists, "Execution environment should not exist");
        assertTrue(executionEnvironment.codehash == bytes32(0), "Execution environment should not exist");

        mockFactory.getOrCreateExecutionEnvironment(userOp);

        (executionEnvironment,, exists) = mockFactory.getExecutionEnvironment(user, address(dAppControl));
        assertTrue(exists, "Execution environment should exist");
        assertFalse(executionEnvironment.codehash == bytes32(0), "Execution environment should exist");
    }

    function test_FactorySaltSetCorrectly() public {
        bytes32 expectedSalt = keccak256(abi.encodePacked(block.chainid, address(mockFactory), "AtlasFactory 1.0"));
        assertEq(expectedSalt, mockFactory.salt(), "Factory salt not set correctly");
    }
}
