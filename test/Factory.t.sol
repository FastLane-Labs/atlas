// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import "../src/contracts/types/CallTypes.sol";
import {ProtocolControl} from "../src/contracts/protocol/ProtocolControl.sol";

contract DummyProtocolControl is ProtocolControl {
    constructor(address escrow)
        ProtocolControl(
            escrow,
            address(0),
            CallConfig(false, false, false, false, false, false, false, false, false, false, false, false, false, false)
        )
    {}

    function _stagingCall(UserMetaTx calldata) internal override returns (bytes memory) {}
    function _allocatingCall(bytes calldata) internal override {}
    function getPayeeData(bytes calldata) external view override returns (PayeeData[] memory) {}
    function getBidFormat(UserMetaTx calldata) external view override returns (BidData[] memory) {}
    function getBidValue(SearcherCall calldata) external view override returns (uint256) {}
}

contract FactoryTest is BaseTest {
    DummyProtocolControl public protocolControl;

    function setUp() public virtual override {
        BaseTest.setUp();

        governancePK = 666;
        governanceEOA = vm.addr(governancePK);
        vm.startPrank(governanceEOA);
        protocolControl = new DummyProtocolControl(escrow);
        vm.stopPrank();
    }

    function testExecutionEnvironmentAddress() public {
        address expectedExecutionEnvironment = 0xf8927cd848a3D1BCA26634E25a89ccE8feb7A65F;

        assertEq(atlas.createExecutionEnvironment(protocolControl.getProtocolCall()), expectedExecutionEnvironment);

        UserMetaTx memory userMetaTx = UserMetaTx({
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
        UserCall memory userCall = UserCall({to: address(0x1), metaTx: userMetaTx, signature: "signature"});

        assertEq(atlas.getExecutionEnvironment(userCall, address(protocolControl)), expectedExecutionEnvironment);
    }

    function testGetEscrowAddress() public {
        assertEq(atlas.getEscrowAddress(), address(atlas));
    }
}
