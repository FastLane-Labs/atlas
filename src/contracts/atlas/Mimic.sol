//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

contract Mimic {
    address immutable public execution;
    address immutable public user;

    constructor(
        address _user,
        address _execution
    ) {
        user = _user;
        execution = _execution;
    }

    receive() external payable {}

    fallback(bytes calldata) external payable returns (bytes memory) {
        (bool success, bytes memory output) = execution.delegatecall(
            abi.encodePacked(msg.data, user)
        );
        if (!success) { revert(); }
        return output;
    }
}