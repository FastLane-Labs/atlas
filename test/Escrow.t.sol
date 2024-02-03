// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import { EscrowBits } from "src/contracts/libraries/EscrowBits.sol";

import { DummyDAppControl } from "./base/DummyDAppControl.sol";
import { AtlasBaseTest } from "./base/AtlasBaseTest.t.sol";
import { DummyDAppControlBuilder } from "./helpers/DummyDAppControlBuilder.sol";
import { CallConfigBuilder } from "./helpers/CallConfigBuilder.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";

import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/EscrowTypes.sol";

contract EscrowTest is AtlasBaseTest {
    using CallBits for CallConfig;

    DummyDAppControl dAppControl;
    DummySolver dummySolver;
    uint256 defaultBidAmount = 1;
    bytes4 noError = 0;
    address invalid = makeAddr("invalid");

    event MEVPaymentSuccess(address bidToken, uint256 bidAmount);
    event MEVPaymentFailure(address indexed controller, uint32 callConfig, address bidToken, uint256 bidAmount);
    event SolverTxResult(
        address indexed solverTo, address indexed solverFrom, bool executed, bool success, uint256 result
    );

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
            .withDapp(address(dAppControl))
            .withControl(address(dAppControl))
            .withSessionKey(address(0))
            .withData("")
            .sign(address(atlasVerification), userPK);
    }

    function validSolverOperation(UserOperation memory userOp) public returns (SolverOperationBuilder) {
        return new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withSolver(address(dummySolver))
            .withControl(userOp.control)
            .withUserOpHash(userOp)
            .withBidToken(userOp)
            .withBidAmount(0)
            .withData("")
            .sign(address(atlasVerification), solverOnePK);
    }

    function validDAppOperation(
        UserOperation memory userOp,
        SolverOperation[] memory solverOps
    )
        public
        returns (DAppOperationBuilder)
    {
        return new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(2_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withBundler(address(0))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .sign(address(atlasVerification), governancePK);
    }

    function defaultAtlasWithCallConfig(CallConfig memory callConfig) public {
        dAppControl = defaultDAppControl().withCallConfig(callConfig).buildAndIntegrate(atlasVerification);
    }

    function setUp() public override {
        super.setUp();

        deal(solverOneEOA, 1 ether);

        vm.startPrank(solverOneEOA);
        dummySolver = new DummySolver(address(atlas));
        atlas.depositAndBond{ value: 1 ether }(1 ether);
        vm.stopPrank();

        deal(address(dummySolver), defaultBidAmount);
    }

    //
    // ---- TESTS BEGIN HERE ---- //
    //

    // Ensure the preOps hook is successfully called. To ensure the hooks' returned data is as expected, we forward it
    // to the solver call; the data field of the solverOperation contains the expected value, the check is made in the
    // solver's atlasSolverCall function, as defined in the DummySolver contract.
    function test_executePreOpsCall_success() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withRequirePreOps(true) // Execute the preOps hook
                .withTrackPreOpsReturnData(true) // Track the preOps hook's return data
                .withForwardReturnData(true) // Forward the preOps hook's return data to the solver call
                .build()
        );
        executeHookCase(false, block.timestamp * 2, noError);
    }

    // Ensure metacall reverts with the proper error when the preOps hook reverts.
    function test_executePreOpsCall_failure() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withRequirePreOps(true) // Execute the preOps hook
                .withReuseUserOp(true) // Allow metacall to revert
                .build()
        );
        executeHookCase(true, 0, AtlasErrors.PreOpsFail.selector);
    }

    // Ensure the user operation executes successfully. To ensure the operation's returned data is as expected, we
    // forward it to the solver call; the data field of the solverOperation contains the expected value, the check is
    // made in the solver's atlasSolverCall function, as defined in the DummySolver contract.
    function test_executeUserOperation_success() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withTrackUserReturnData(true) // Track the user operation's return data
                .withForwardReturnData(true) // Forward the user operation's return data to the solver call
                .build()
        );
        executeHookCase(false, block.timestamp * 3, noError);
    }

    // Ensure metacall reverts with the proper error when the user operation reverts.
    function test_executeUserOperation_failure() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withReuseUserOp(true) // Allow metacall to revert
                .build()
        );
        executeHookCase(true, 0, AtlasErrors.UserOpFail.selector);
    }

    // Ensure the postOps hook is successfully called. No return data is expected from the postOps hook, so we do not
    // forward any data to the solver call.
    function test_executePostOpsCall_success() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withRequirePostOps(true) // Execute the postOps hook
                .build()
        );
        executeHookCase(false, 0, noError);
    }

    // Ensure metacall reverts with the proper error when the postOps hook reverts.
    function test_executePostOpsCall_failure() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withTrackUserReturnData(true) // Track the user operation's return data
                .withForwardReturnData(true) // Forward the user operation's return data to the solver call
                .withRequirePostOps(true) // Execute the postOps hook
                .withReuseUserOp(true) // Allow metacall to revert
                .build()
        );
        executeHookCase(false, 1, AtlasErrors.PostOpsFail.selector);
    }

    // Ensure the allocateValue hook is successfully called. No return data is expected from the allocateValue hook, so
    // we check by emitting an event in the hook. The emitter must be the executionEnvironment since allocateValue is
    // delegatecalled.
    function test_allocateValue_success() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withTrackUserReturnData(true) // Track the user operation's return data
                .build()
        );

        vm.prank(userEOA);
        address executionEnvironment = atlas.createExecutionEnvironment(address(dAppControl));

        vm.expectEmit(false, false, false, true, executionEnvironment);
        emit MEVPaymentSuccess(address(0), defaultBidAmount);
        this.executeHookCase(false, 0, noError);
    }

    // Ensure the proper event is emitted when allocateValue fails.
    function test_allocateValue_failure() public {
        CallConfig memory callConfig = defaultCallConfig()
            .withTrackUserReturnData(true) // Track the user operation's return data
            .build();
        defaultAtlasWithCallConfig(callConfig);

        vm.expectEmit(false, false, false, true, address(atlas));
        emit MEVPaymentFailure(address(dAppControl), callConfig.encodeCallConfig(), address(0), defaultBidAmount);
        this.executeHookCase(false, 1, noError);
    }

    function executeHookCase(bool hookShouldRevert, uint256 expectedHookReturnValue, bytes4 expectedError) public {
        bool revertExpected = expectedError != noError;

        UserOperation memory userOp = validUserOperation()
            .withData(
                abi.encodeWithSelector(
                    dAppControl.userOperationCall.selector,
                    hookShouldRevert,
                    expectedHookReturnValue
                )
            )
            .signAndBuild(address(atlasVerification), userPK);

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withBidAmount(defaultBidAmount)
            .withData(abi.encode(expectedHookReturnValue))
            .signAndBuild(address(atlasVerification), solverOnePK);

        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        if (revertExpected) {
            vm.expectRevert(expectedError);
        }

        vm.prank(userEOA);
        bool auctionWon = atlas.metacall(userOp, solverOps, dappOp);
        
        if (!revertExpected) {
            assertTrue(auctionWon, "auction should have been won");
        }
    }

    function test_executeSolverOperation_validateSolverOperation_invalidTo() public {
        // This test can't pass with metacall as the entrypoint, because a solverOp with an invalid .to will
        // be filtered out by the AtlasVerification contract, before reaching executeSolverOperation.
        vm.skip(true);

        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        solverOps[0] = validSolverOperation(userOp)
            .withTo(invalid)
            .withBidAmount(defaultBidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
        executeSolverOperationCase(userOp, solverOps, false, false, 1 << uint256(SolverOutcome.InvalidTo), true);
    }

    function test_executeSolverOperation_validateSolverOperation_perBlockLimit() public {
        vm.prank(solverOneEOA);
        atlas.unbond(1); // This will set the solver's lastAccessedBlock to the current block

        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        executeSolverOperationCase(userOp, solverOps, false, false, 1 << uint256(SolverOutcome.PerBlockLimit), true);
    }

    function test_executeSolverOperation_validateSolverOperation_insufficientEscrow() public {
        vm.txGasPrice(1e50); // Set a gas price that will cause the solver to run out of escrow

        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        executeSolverOperationCase(userOp, solverOps, false, false, 1 << uint256(SolverOutcome.InsufficientEscrow), true);
    }

    function test_executeSolverOperation_validateSolverOperation_callValueTooHigh() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        solverOps[0] = validSolverOperation(userOp)
            .withValue(100 ether) // Set a call value that is too high
            .withBidAmount(defaultBidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
        executeSolverOperationCase(userOp, solverOps, false, false, 1 << uint256(SolverOutcome.CallValueTooHigh), true);
    }

    function test_executeSolverOperation_validateSolverOperation_userOutOfGas() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        this.executeSolverOperationCase{gas: EscrowBits.VALIDATION_GAS_LIMIT + EscrowBits.SOLVER_GAS_LIMIT + 1_000_000}(
            userOp, solverOps, false, false, 1 << uint256(SolverOutcome.UserOutOfGas), true
        );
    }

    function test_executeSolverOperation_solverOpWrapper_success() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        uint256 result = (1 << uint256(SolverOutcome.Success)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, true, result, false);
    }

    function test_executeSolverOperation_solverOpWrapper_solverBidUnpaid() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        solverOps[0] = validSolverOperation(userOp)
            .withBidAmount(defaultBidAmount * 2) // Solver's contract doesn't have that much
            .signAndBuild(address(atlasVerification), solverOnePK);
        uint256 result = (1 << uint256(SolverOutcome.BidNotPaid)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_solverMsgValueUnpaid() public {
        uint256 bidAmount = dummySolver.noGasPayBack(); // Special bid value that will cause the solver to not call reconcile
        deal(address(dummySolver), bidAmount);

        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        solverOps[0] = validSolverOperation(userOp)
            .withBidAmount(bidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
        uint256 result = (1 << uint256(SolverOutcome.CallValueTooHigh)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_intentUnfulfilled() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(
            defaultCallConfig()
                .withTrackPreOpsReturnData(true)
                .withTrackUserReturnData(true)
                .withRequirePreOps(true)
                .withPostSolver(true)
                .build()
        );
        uint256 result = (1 << uint256(SolverOutcome.IntentUnfulfilled)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_solverOperationReverted() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(
            defaultCallConfig()
                .withTrackUserReturnData(true)
                .withForwardReturnData(true)
                .build()
        );
        solverOps[0] = validSolverOperation(userOp)
            .withData(abi.encode(1))
            .withBidAmount(defaultBidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
        uint256 result = (1 << uint256(SolverOutcome.CallReverted)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_alteredControlHash() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(defaultCallConfig().build());
        solverOps[0] = validSolverOperation(userOp)
            .withControl(invalid) // Set an invalid dApp controller
            .withBidAmount(defaultBidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
        uint256 result = (1 << uint256(SolverOutcome.InvalidControlHash)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_preSolverFailed() public {
        (UserOperation memory userOp, SolverOperation[] memory solverOps) = executeSolverOperationInit(
            defaultCallConfig()
                .withTrackPreOpsReturnData(true)
                .withTrackUserReturnData(true)
                .withRequirePreOps(true)
                .withPreSolver(true)
                .build()
        );
        uint256 result = (1 << uint256(SolverOutcome.PreSolverFailed)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_postSolverFailed() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withTrackPreOpsReturnData(true)
                .withTrackUserReturnData(true)
                .withRequirePreOps(true)
                .withPostSolver(true)
                .build()
        );

        UserOperation memory userOp = validUserOperation()
            .withData(abi.encodeWithSelector(dAppControl.userOperationCall.selector, false, 1))
            .signAndBuild(address(atlasVerification), userPK);
        
        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withBidAmount(defaultBidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
        
        uint256 result = (1 << uint256(SolverOutcome.IntentUnfulfilled)) | (1 << uint256(SolverOutcome.ExecutionCompleted));
        executeSolverOperationCase(userOp, solverOps, true, false, result, true);
    }

    function test_executeSolverOperation_solverOpWrapper_defaultCase() public {
        // Can't find a way to reach the default case (which is a good thing)
        vm.skip(true);
    }

    function executeSolverOperationInit(CallConfig memory callConfig)
        public
        returns (UserOperation memory userOp, SolverOperation[] memory solverOps)
    {
        defaultAtlasWithCallConfig(callConfig);

        userOp = validUserOperation()
            .withData(abi.encodeWithSelector(dAppControl.userOperationCall.selector, false, 0))
            .signAndBuild(address(atlasVerification), userPK);
        
        solverOps = new SolverOperation[](1);
        solverOps[0] = validSolverOperation(userOp)
            .withBidAmount(defaultBidAmount)
            .signAndBuild(address(atlasVerification), solverOnePK);
    }

    function executeSolverOperationCase(
        UserOperation memory userOp,
        SolverOperation[] memory solverOps,
        bool solverOpExecuted,
        bool solverOpSuccess,
        uint256 expectedResult,
        bool metacallShouldRevert
    )
        public
    {
        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        vm.expectEmit(false, false, false, true, address(atlas));
        emit SolverTxResult(solverOps[0].solver, solverOps[0].from, solverOpExecuted, solverOpSuccess, expectedResult);

        vm.prank(userEOA);
        if (metacallShouldRevert) vm.expectRevert(); // Metacall should revert, the reason isn't important, we're only checking the event
        atlas.metacall(userOp, solverOps, dappOp);
    }
}

contract DummySolver {
    uint256 public noGasPayBack = 123456789;
    address private _atlas;

    constructor(address atlas) {
        _atlas = atlas;
    }

    function atlasSolverCall(
        address sender,
        address,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata extraReturnData
    )
        external
        payable
        returns (bool, bytes memory)
    {
        if (solverOpData.length > 0 && extraReturnData.length > 0) {
            (uint256 solverDataValue) = abi.decode(solverOpData, (uint256));
            (uint256 extraDataValue) = abi.decode(extraReturnData, (uint256));
            require(solverDataValue == extraDataValue, "solver data and extra data do not match");
        }

        // Pay bid
        if (address(this).balance >= bidAmount) {
            SafeTransferLib.safeTransferETH(msg.sender, bidAmount);
        }

        // Pay gas
        if (bidAmount != noGasPayBack) {
            uint256 shortfall = IEscrow(_atlas).shortfall();
            IEscrow(_atlas).reconcile(msg.sender, sender, shortfall);
        }

        return (true, new bytes(0));
    }
}
