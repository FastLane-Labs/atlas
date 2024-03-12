// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { DAppConfig, DAppOperation, CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";
import { CallConfigBuilder } from "./helpers/CallConfigBuilder.sol";
import { DummyDAppControlBuilder } from "./helpers/DummyDAppControlBuilder.sol";

import { DummyDAppControl } from "./base/DummyDAppControl.sol";


contract SimulatorTest is BaseTest {

    DummyDAppControl dAppControl;

    struct ValidCallsCall {
        UserOperation userOp;
        SolverOperation[] solverOps;
        DAppOperation dAppOp;
        uint256 msgValue;
        address msgSender;
        bool isSimulation;
    }

    function defaultCallConfig() public returns (CallConfigBuilder) {
        return new CallConfigBuilder();
    }

    function defaultDAppControl() public returns (DummyDAppControlBuilder) {
        return new DummyDAppControlBuilder()
            .withEscrow(address(atlas))
            .withGovernance(governanceEOA)
            .withCallConfig(defaultCallConfig().build());
    }

    function validUserOperation() public returns (UserOperationBuilder) {
        return new UserOperationBuilder()
            .withFrom(userEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(tx.gasprice + 1)
            .withNonce(address(atlasVerification), userEOA)
            .withDeadline(block.number + 2)
            .withControl(address(dAppControl))
            .withSessionKey(address(0))
            .withData("")
            .sign(address(atlasVerification), userPK);
    }

    function setUp() public override {
        BaseTest.setUp();
        dAppControl = defaultDAppControl().buildAndIntegrate(atlasVerification);
    }

    function test_sim_temp() public {
        
        // Fail in VERIFICATION.validateCalls with userSignatureInvalid

        UserOperation memory userOp = validUserOperation().build();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPK, "wrong data");
        userOp.signature = abi.encodePacked(r, s, v);

        simulator.simUserOperation(userOp);
    }
    
    function test_simUserOperation_success_valid() public {}

    function test_simUserOperation_fail_GasPriceHigherThanMax() public {}

    function test_simUserOperation_fail_TxValueLowerThanCallValue() public {}

    function test_simUserOperation_fail_DAppSignatureInvalid() public {}

    function test_simUserOperation_fail_UserSignatureInvalid() public {}

    function test_simUserOperation_fail_TooManySolverOps() public {}

    function test_simUserOperation_fail_UserDeadlineReached() public {}

    function test_simUserOperation_fail_DAppDeadlineReached() public {}

    function test_simUserOperation_fail_ExecutionEnvEmpty() public {}

    function test_simUserOperation_fail_NoSolverOp() public {}

    function test_simUserOperation_fail_UnknownAuctioneerNotAllowed() public {}

    function test_simUserOperation_fail_InvalidSequence() public {}

    function test_simUserOperation_fail_InvalidAuctioneer() public {}

    function test_simUserOperation_fail_InvalidBundler() public {}

    function test_simUserOperation_fail_OpHashMismatch() public {}

    function test_simUserOperation_fail_DeadlineMismatch() public {}

    function test_simUserOperation_fail_InvalidControl() public {}

    function test_simUserOperation_fail_InvalidDAppNonce() public {}

}