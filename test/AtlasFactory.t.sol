// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Atlas } from "src/contracts/atlas/Atlas.sol";
import { AtlasFactory } from "src/contracts/atlas/AtlasFactory.sol";
import { TestConstants } from "./base/TestConstants.sol";

import { Simulator } from "src/contracts/helpers/Simulator.sol";

import { DummyDAppControl } from "./helpers/DAppControl.sol";
import { CallConfigFactory } from "./helpers/CallConfigFactory.sol";

import { CallConfig } from "../src/contracts/types/DAppApprovalTypes.sol";

import "forge-std/console.sol";

contract AtlasFactoryTest is Test {
    AtlasFactory public atlasFactory;

    function setUp() public virtual {
        atlasFactory = new AtlasFactory(address(0));
    }

    function testCreateExecutionEnvironment() public {
        vm.startPrank(address(0));

        CallConfig memory cc = CallConfigFactory.allFalseCallConfig();
        DummyDAppControl dc = new DummyDAppControl(address(0), address(0), cc);
    
        address ee = atlasFactory.createExecutionEnvironment(address(0), address(dc));
    }
}
