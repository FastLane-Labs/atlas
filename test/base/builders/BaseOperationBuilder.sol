// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract BaseOperationBuilder {
    uint8 public v;
    bytes32 public r;
    bytes32 public s;

    function _atlas() internal virtual returns (address) { }

    function _atlasVerification() internal virtual returns (address) { }
}
