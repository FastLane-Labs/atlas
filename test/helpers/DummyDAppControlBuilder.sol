// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DummyDAppControl } from "../base/DummyDAppControl.sol";
import { CallConfig } from "../../src/contracts/types/DAppApprovalTypes.sol";
import { AtlasVerification } from "../../src/contracts/atlas/AtlasVerification.sol";

import "forge-std/Test.sol";


contract DummyDAppControlBuilder is Test {
    address public escrow;
    address public governance;
    CallConfig callConfig;

    function withEscrow(address _escrow) public returns (DummyDAppControlBuilder) {
        escrow = _escrow;
        return this;
    }

    function withGovernance(address _governance) public returns (DummyDAppControlBuilder) {
        governance = _governance;
        return this;
    }

    function withCallConfig(CallConfig memory _callConfig) public returns (DummyDAppControlBuilder) {
        callConfig = _callConfig;
        return this;
    }

    function build() public returns (DummyDAppControl) {
        return new DummyDAppControl(
            escrow,
            governance,
            callConfig
        );
    }

    /*
    * @notice Builds a DummyDAppControl contract and integrates it with the AtlasVerification contract.
    * @param verification The AtlasVerification contract to integrate with.
    * @return The DummyDAppControl contract.
    */
    function buildAndIntegrate(AtlasVerification verification) public returns (DummyDAppControl) {
        vm.startPrank(governance);
        DummyDAppControl control = build();
        verification.initializeGovernance(address(control));
        verification.integrateDApp(address(control));
        vm.stopPrank();
        return control;
    }
}
