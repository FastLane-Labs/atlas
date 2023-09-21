// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import "../src/contracts/types/CallTypes.sol";
import {DAppControl} from "../src/contracts/dapp/DAppControl.sol";

contract DummyDAppControl is DAppControl {
    constructor(address escrow)
        DAppControl(
            escrow,
            address(0),
            CallConfig(false, false, false, false, false, false, false, false, false, false, false, false, false, false)
        )
    {}

    function _preOpsCall(UserCall calldata) internal override returns (bytes memory) {}
    function _allocateValueCall(bytes calldata) internal override {}
    function getPayeeData(bytes calldata) external view override returns (PayeeData[] memory) {}
    function getBidFormat(UserCall calldata) external view override returns (BidData[] memory) {}
    function getBidValue(SolverOperation calldata) external view override returns (uint256) {}
}

contract FactoryTest is BaseTest {
    DummyDAppControl public dAppControl;

    function setUp() public virtual override {
        BaseTest.setUp();

        governancePK = 666;
        governanceEOA = vm.addr(governancePK);
        vm.startPrank(governanceEOA);
        dAppControl = new DummyDAppControl(escrow);
        vm.stopPrank();
    }

    function testExecutionEnvironmentAddress() public {
        address expectedExecutionEnvironment = 0xc7B4e21c1eB2C5Cf0B3D59657851DdCd98aCEa32;

        assertEq(
            atlas.createExecutionEnvironment(dAppControl.getDAppConfig()),
            expectedExecutionEnvironment,
            "Create exec env address not same as predicted"
        );

        UserCall memory uCall = UserCall({
            from: address(this),
            to: address(0x2),
            deadline: 12,
            gas: 34,
            nonce: 56,
            maxFeePerGas: 78,
            value: 90,
            control: address(0x3),
            data: "data"
        });
        UserOperation memory userOp = UserOperation({to: address(0x1), call: uCall, signature: "signature"});

        assertEq(
            atlas.getExecutionEnvironment(userOp, address(dAppControl)),
            expectedExecutionEnvironment,
            "atlas.getExecEnv address not same as predicted"
        );
    }

    function testGetEscrowAddress() public {
        assertEq(atlas.getEscrowAddress(), address(atlas));
    }
}
