// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import "forge-std/Test.sol";

contract DeleteThisTest is Test {
    function setUp() public {

    }

    function testValueStartedInside() public {

    }
}


contract ValueSender1 {
    function sendValue(address target, uint256 amount) public {
        require(address(this).balance >= amount, "ValueSender1: insufficient balance");
        target.call{value: amount}("");
    }
}

contract ValueReceiver2 {
    uint256 public valueReceived;

    function receiveValue() public payable {
        valueReceived += msg.value;
    }

    fallback() external payable {}
    receive() external payable {}
}