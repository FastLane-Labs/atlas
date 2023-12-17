// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Factory } from "../src/contracts/atlas/Factory.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";

import "../src/contracts/types/UserCallTypes.sol";

import "./base/TestUtils.sol";

contract MockFactory is Factory, Test {
    function getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        external
        returns (address executionEnvironment, DAppConfig memory dConfig)
    {
        return _getOrCreateExecutionEnvironment(userOp);
    }

    function deployExecutionEnvironmentTemplate(address caller) external returns (address executionEnvironment) {
        vm.prank(caller);
        executionEnvironment = _deployExecutionEnvironmentTemplate();
    }
}

contract FactoryTest is Test {
    MockFactory public mockFactory;
    DummyDAppControl public dAppControl;

    address public user;

    function setUp() public {
        mockFactory = new MockFactory();
        dAppControl = new DummyDAppControl(address(0), address(0));
        user = address(999);
    }

    function test_createExecutionEnvironment() public {
        uint32 callConfig = dAppControl.callConfig();
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

    function test_deployExecutionEnvironmentTemplate() public {
        address executionEnvironment = mockFactory.deployExecutionEnvironmentTemplate(user);
        assertFalse(executionEnvironment.codehash == bytes32(0), "Execution environment should exist");
    }
}
