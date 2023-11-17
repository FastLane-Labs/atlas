// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import {DAppControl} from "../src/contracts/dapp/DAppControl.sol";
import "../src/contracts/types/UserCallTypes.sol";
import "./base/TestUtils.sol";

contract DummyDAppControl is DAppControl {
    constructor(address escrow)
        DAppControl(
            escrow,
            address(0),
            CallConfig(
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false,
                false
            )
        )
    {}

    function _preOpsCall(UserOperation calldata) internal override returns (bytes memory) {}
    function _allocateValueCall(address, uint256, bytes calldata) internal override {}
    // function getPayeeData(bytes calldata) external view override returns (PayeeData[] memory) {}
    function getBidFormat(UserOperation calldata) public view override returns (address) {}
    function getBidValue(SolverOperation calldata) public view override returns (uint256) {}
}

contract FactoryTest is BaseTest {
    DummyDAppControl public dAppControl;

    // TODO fix this to test AtlasFactory instead
    
    // function setUp() public virtual override {
    //     BaseTest.setUp();

    //     governancePK = 666;
    //     governanceEOA = vm.addr(governancePK);
    //     vm.startPrank(governanceEOA);
    //     dAppControl = new DummyDAppControl(escrow);
    //     vm.stopPrank();
    // }

    // function testExecutionEnvironmentAddress() public {
    //     UserOperation memory userOp = UserOperation({
    //         from: address(this),
    //         to: address(atlas),
    //         deadline: 12,
    //         gas: 34,
    //         nonce: 56,
    //         maxFeePerGas: 78,
    //         value: 90,
    //         dapp: address(0x2),
    //         control: address(0x3),
    //         data: "data",
    //         signature: "signature"
    //     });

    //     address expectedExecutionEnvironment =
    //         TestUtils.computeExecutionEnvironment(payable(atlas), userOp, address(dAppControl));

    //     assertEq(
    //         atlas.createExecutionEnvironment(address(dAppControl)),
    //         expectedExecutionEnvironment,
    //         "Create exec env address not same as predicted"
    //     );

    //     (address executionEnvironment,,) = atlas.getExecutionEnvironment(userOp.from, address(dAppControl));
    //     assertEq(
    //         executionEnvironment,
    //         expectedExecutionEnvironment,
    //         "atlas.getExecEnv address not same as predicted"
    //     );
    // }
}
