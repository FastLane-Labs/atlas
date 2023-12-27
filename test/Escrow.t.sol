// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";
import { FastLaneErrorsEvents } from "../src/contracts/types/Emissions.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";
import { AtlasBaseTest } from "./base/AtlasBaseTest.t.sol";
import { DummyDAppControlBuilder } from "./helpers/DummyDAppControlBuilder.sol";
import { CallConfigBuilder } from "./helpers/CallConfigBuilder.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";

import "../src/contracts/types/UserCallTypes.sol";
import "../src/contracts/types/SolverCallTypes.sol";
import "../src/contracts/types/DAppApprovalTypes.sol";

contract EscrowTest is AtlasBaseTest {
    DummyDAppControl dAppControl;
    DummySolver dummySolver;

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

        deal(address(dummySolver), 1);
    }

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
        executeCase(false, block.timestamp * 2, 0);
    }

    // Ensure metacall reverts with the proper error code when the preOps hook reverts.
    function test_executePreOpsCall_failure() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withRequirePreOps(true) // Execute the preOps hook
                .withReuseUserOp(true) // Allow metacall to revert
                .build()
        );
        executeCase(true, 0, FastLaneErrorsEvents.PreOpsFail.selector);
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
        executeCase(false, block.timestamp * 3, 0);
    }

    // Ensure metacall reverts with the proper error code when the user operation reverts.
    function test_executeUserOperation_failure() public {
        defaultAtlasWithCallConfig(
            defaultCallConfig()
                .withReuseUserOp(true) // Allow metacall to revert
                .build()
        );
        executeCase(true, 0, FastLaneErrorsEvents.UserOpFail.selector);
    }

    function executeCase(bool hookShouldRevert, uint256 expectedHookReturnValue, bytes4 expectedError) public {
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
            .withBidAmount(1)
            .withData(abi.encode(expectedHookReturnValue))
            .signAndBuild(address(atlasVerification), solverOnePK);

        DAppOperation memory dappOp = validDAppOperation(userOp, solverOps).build();

        if (hookShouldRevert) {
            vm.expectRevert(expectedError);
        }

        vm.prank(userEOA);
        bool auctionWon = atlas.metacall(userOp, solverOps, dappOp);
        
        if (!hookShouldRevert) {
            assertTrue(auctionWon, "Auction should have been won");
        }
    }
}

contract DummySolver {
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
        returns (bool success, bytes memory data)
    {
        if (solverOpData.length > 0 && extraReturnData.length > 0) {
            (uint256 solverDataValue) = abi.decode(solverOpData, (uint256));
            (uint256 extraDataValue) = abi.decode(extraReturnData, (uint256));
            require(solverDataValue == extraDataValue, "Solver data and extra data do not match");
        }

        // Pay bid
        SafeTransferLib.safeTransferETH(msg.sender, bidAmount);

        // Pay gas
        uint256 shortfall = IEscrow(_atlas).shortfall();
        IEscrow(_atlas).reconcile(msg.sender, sender, shortfall);

        success = true;
    }
}
