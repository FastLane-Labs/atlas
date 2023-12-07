// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Factory as AbstractFactory } from "../src/contracts/atlas/Factory.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";

import "../src/contracts/types/UserCallTypes.sol";

import "./base/TestUtils.sol";

contract Factory is AbstractFactory {
    function getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        external
        returns (address executionEnvironment, DAppConfig memory dConfig)
    {
        return _getOrCreateExecutionEnvironment(userOp);
    }
}

contract FactoryTest is Test {
    Factory public factory;
    DummyDAppControl public dAppControl;

    address public user;

    function setUp() public {
        factory = new Factory();
        dAppControl = new DummyDAppControl(address(0));
        user = address(999);
    }

    function test_createExecutionEnvironment() public {
        uint32 callConfig = dAppControl.callConfig();
        bytes memory creationCode = TestUtils._getMimicCreationCode(
            address(dAppControl), callConfig, factory.executionTemplate(), user, address(dAppControl).codehash
        );
        address expectedExecutionEnvironment = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), factory.salt(), keccak256(abi.encodePacked(creationCode))
                        )
                    )
                )
            )
        );

        assertTrue(expectedExecutionEnvironment.codehash == bytes32(0));

        vm.prank(user);
        address actualExecutionEnvironment = factory.createExecutionEnvironment(address(dAppControl));

        assertFalse(expectedExecutionEnvironment.codehash == bytes32(0));
        assertEq(
            expectedExecutionEnvironment, actualExecutionEnvironment, "Execution environment not the same as predicted"
        );
    }

    function test_getExecutionEnvironment() public {
        address executionEnvironment;
        bool exists;

        (executionEnvironment,, exists) = factory.getExecutionEnvironment(user, address(dAppControl));
        assertFalse(exists, "Execution environment should not exist");
        assertTrue(executionEnvironment.codehash == bytes32(0));

        vm.prank(user);
        factory.createExecutionEnvironment(address(dAppControl));

        (executionEnvironment,, exists) = factory.getExecutionEnvironment(user, address(dAppControl));
        assertTrue(exists, "Execution environment should exist");
        assertFalse(executionEnvironment.codehash == bytes32(0));
    }

    function test_getOrCreateExecutionEnvironment() public {
        UserOperation memory userOp;
        userOp.from = user;
        userOp.control = address(dAppControl);

        address executionEnvironment;
        bool exists;

        (executionEnvironment,, exists) = factory.getExecutionEnvironment(user, address(dAppControl));
        assertFalse(exists, "Execution environment should not exist");
        assertTrue(executionEnvironment.codehash == bytes32(0));

        factory.getOrCreateExecutionEnvironment(userOp);

        (executionEnvironment,, exists) = factory.getExecutionEnvironment(user, address(dAppControl));
        assertTrue(exists, "Execution environment should exist");
        assertFalse(executionEnvironment.codehash == bytes32(0));
    }
}
