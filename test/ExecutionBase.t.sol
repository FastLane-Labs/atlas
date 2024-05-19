// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { BaseTest } from "./base/BaseTest.t.sol";

import { Base } from "src/contracts/common/ExecutionBase.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";

import { EXECUTION_PHASE_OFFSET } from "src/contracts/libraries/SafetyBits.sol";

import "src/contracts/libraries/SafetyBits.sol";

contract ExecutionBaseTest is BaseTest {
    using SafetyBits for EscrowKey;

    MockExecutionEnvironment public mockExecutionEnvironment;
    address user;
    address dAppControl;
    uint32 callConfig;
    bytes randomData;

    function setUp() public override {
        super.setUp();

        mockExecutionEnvironment = new MockExecutionEnvironment(address(atlas));
        user = address(0x2222);
        dAppControl = address(0x3333);
        callConfig = 888;
        randomData = "0x1234";
    }

    function test_forward() public {
        (bytes memory firstSet, EscrowKey memory _escrowKey) = forwardGetFirstSet(SafetyBits._LOCKED_X_PRE_OPS_X_UNSET);
        bytes memory secondSet = abi.encodePacked(user, dAppControl, callConfig);

        bytes memory expected = bytes.concat(randomData, firstSet, secondSet);

        bytes memory data = abi.encodeWithSelector(MockExecutionEnvironment.forward_.selector, randomData);
        executeForwardCase("forward", data, _escrowKey, expected);
    }

    function test_forwardSpecial_standard() public {
        (bytes memory firstSet, EscrowKey memory _escrowKey) = forwardGetFirstSet(SafetyBits._LOCKED_X_PRE_OPS_X_UNSET);
        bytes memory secondSet = abi.encodePacked(user, dAppControl, callConfig);

        bytes memory expected = bytes.concat(randomData, firstSet, secondSet);

        bytes memory data = abi.encodeWithSelector(MockExecutionEnvironment.forwardSpecial_.selector, randomData);
        executeForwardCase("forwardSpecial_standard", data, _escrowKey, expected);
    }

    function test_forwardSpecial_phaseSwitch() public {
        (bytes memory firstSet, EscrowKey memory _escrowKey) =
            forwardGetFirstSet(SafetyBits._LOCKED_X_SOLVERS_X_REQUESTED);
        bytes memory secondSet = abi.encodePacked(user, dAppControl, callConfig);

        bytes memory expected = bytes.concat(randomData, firstSet, secondSet);

        bytes memory data = abi.encodeWithSelector(MockExecutionEnvironment.forwardSpecial_.selector, randomData);
        executeForwardCase("forwardSpecial_phaseSwitch", data, _escrowKey, expected);
    }

    function executeForwardCase(
        string memory testName,
        bytes memory data,
        EscrowKey memory escrowKey,
        bytes memory expected
    )
        internal
    {
        data = abi.encodePacked(data, escrowKey.pack());

        // Mimic the Mimic
        data = abi.encodePacked(data, user, dAppControl, callConfig);

        (, bytes memory result) = address(mockExecutionEnvironment).call(data);
        result = abi.decode(result, (bytes));

        assertEq(result, expected, testName);
    }

    function forwardGetFirstSet(uint16 lockState)
        public
        pure
        returns (bytes memory firstSet, EscrowKey memory _escrowKey)
    {
        _escrowKey = EscrowKey({
            executionEnvironment: address(0),
            userOpHash: bytes32(0),
            bundler: address(0),
            addressPointer: address(0x1111),
            solverSuccessful: false,
            paymentsSuccessful: true,
            callIndex: 0,
            callCount: 1,
            lockState: lockState,
            solverOutcome: 2,
            bidFind: true,
            isSimulation: true,
            callDepth: 1
        });

        if (lockState & 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations)) != 0) {
            lockState = uint16(1) << uint16(BaseLock.Active)
                | uint16(1) << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.PreSolver));
        }

        firstSet = abi.encodePacked(
            _escrowKey.addressPointer,
            _escrowKey.solverSuccessful,
            _escrowKey.paymentsSuccessful,
            _escrowKey.callIndex,
            _escrowKey.callCount,
            lockState,
            _escrowKey.solverOutcome,
            _escrowKey.bidFind,
            _escrowKey.isSimulation,
            _escrowKey.callDepth + 1
        );
    }
}

contract MockExecutionEnvironment is Base {
    constructor(address _atlas) Base(_atlas) { }

    function forward_(bytes memory data) external pure returns (bytes memory) {
        return forward(data);
    }

    function forwardSpecial_(bytes memory data) external pure returns (bytes memory) {
        return forwardSpecial(data, ExecutionPhase.PreSolver);
    }
}
