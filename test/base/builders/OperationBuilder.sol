// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./UserOperationBuilder.sol";
import "./SolverOperationBuilder.sol";
import "./DAppOperationBuilder.sol";

contract OperationBuilder is UserOperationBuilder, SolverOperationBuilder, DAppOperationBuilder {
    address public immutable atlas;
    address public immutable atlasVerification;

    constructor(address atlas_, address atlasVerification_) {
        atlas = atlas_;
        atlasVerification = atlasVerification_;
    }

    function _atlas() internal view override returns (address) {
        return atlas;
    }

    function _atlasVerification() internal view override returns (address) {
        return atlasVerification;
    }
}
