// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { DummyDAppControl } from "./base/DummyDAppControl.sol";
import { DummyDAppControlBuilder } from "./helpers/DummyDAppControlBuilder.sol";
import { CallConfigBuilder } from "./helpers/CallConfigBuilder.sol";
import { UserOperationBuilder } from "./base/builders/UserOperationBuilder.sol";
import { SolverOperationBuilder } from "./base/builders/SolverOperationBuilder.sol";
import { DAppOperationBuilder } from "./base/builders/DAppOperationBuilder.sol";

import { AtlasErrors } from "../src/contracts/types/AtlasErrors.sol";
import { IDAppControl } from "../src/contracts/interfaces/IDAppControl.sol";
import { CallConfig } from "../src/contracts/types/ConfigTypes.sol";

import "../src/contracts/types/UserOperation.sol";
import "../src/contracts/types/SolverOperation.sol";
import "../src/contracts/types/DAppOperation.sol";

contract NoopSolver {
    function atlasSolverCall(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external payable { }
}

contract AtlasErrorBubbleTest is BaseTest {

    DummyDAppControl dAppControl;
    NoopSolver noopSolver;

    function _deployControl(CallConfig memory callConfig) internal returns (DummyDAppControl) {
        return new DummyDAppControlBuilder()
            .withEscrow(address(atlas))
            .withGovernance(governanceEOA)
            .withCallConfig(callConfig)
            .buildAndIntegrate(atlasVerification);
    }

    function test_bubbles_app_revert_inside_atlas_errors_preOps() public {
        // Require preOps and allow reuse so Atlas reverts and bubbles the revert payload
        CallConfig memory cfg = new CallConfigBuilder()
            .withRequirePreOps(true)
            .withReuseUserOp(true)
            .build();

        dAppControl = _deployControl(cfg);
        noopSolver = new NoopSolver();

        // Configure DAppControl to revert during preOps
        dAppControl.setPreOpsShouldRevert(true);

        // Build a minimal metacall
        UserOperation memory userOp = new UserOperationBuilder()
            .withFrom(userEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(tx.gasprice + 1)
            .withNonce(address(atlasVerification), userEOA)
            .withDeadline(block.number + 2)
            .withDapp(address(dAppControl))
            .withControl(address(dAppControl))
            .withCallConfig(IDAppControl(address(dAppControl)).CALL_CONFIG())
            .withDAppGasLimit(IDAppControl(address(dAppControl)).getDAppGasLimit())
            .withSolverGasLimit(IDAppControl(address(dAppControl)).getSolverGasLimit())
            .withBundlerSurchargeRate(IDAppControl(address(dAppControl)).getBundlerSurchargeRate())
            .withSessionKey(address(0))
            .withData("")
            .signAndBuild(address(atlasVerification), userPK);

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = new SolverOperationBuilder()
            .withFrom(solverOneEOA)
            .withTo(address(atlas))
            .withValue(0)
            .withGas(1_000_000)
            .withMaxFeePerGas(userOp.maxFeePerGas)
            .withDeadline(userOp.deadline)
            .withSolver(address(noopSolver))
            .withControl(userOp.control)
            .withUserOpHash(userOp)
            .withBidToken(userOp)
            .withBidAmount(0)
            .withData("")
            .signAndBuild(address(atlasVerification), solverOnePK);

        DAppOperation memory dappOp = new DAppOperationBuilder()
            .withFrom(governanceEOA)
            .withTo(address(atlas))
            .withNonce(address(atlasVerification), governanceEOA)
            .withDeadline(userOp.deadline)
            .withControl(userOp.control)
            .withBundler(address(0))
            .withUserOpHash(userOp)
            .withCallChainHash(userOp, solverOps)
            .signAndBuild(address(atlasVerification), governancePK);

        uint256 gasLim = _gasLim(userOp, solverOps);

        // Execute and capture revert data
        vm.prank(userEOA);
        try atlas.metacall{ gas: gasLim }(userOp, solverOps, dappOp, address(0)) returns (bool) {
            fail();
        } catch (bytes memory revertData) {
            console2.logBytes(revertData);
            assertGt(revertData.length, 8, "revert payload too short");
            // Top-level Atlas error selector must be first 4 bytes
            bytes4 top = bytes4(revertData);
            assertEq(top, AtlasErrors.PreOpsFail.selector, "top-level selector");

            // Next 4 bytes should be the ExecutionEnvironment's Atlas error selector
            // PreOpsDelegatecallFail
            bytes4 inner;
            {
                uint64 head64;
                assembly {
                    head64 := shr(192, mload(add(revertData, 32)))
                }
                inner = bytes4(uint32(head64));
            }
            assertEq(inner, AtlasErrors.PreOpsDelegatecallFail.selector, "inner EE selector");

            // Remaining bytes include the app revert payload (e.g., Error(string))
            assertGt(revertData.length, 8, "missing app payload after selectors");
        }
    }
}
