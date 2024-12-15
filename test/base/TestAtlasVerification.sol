//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../src/contracts/atlas/AtlasVerification.sol";

/// @title TestAtlasVerification
/// @author FastLane Labs
/// @notice A test version of the AtlasVerification to expose internal functions.
contract TestAtlasVerification is AtlasVerification {
    constructor(address atlas) AtlasVerification(atlas) { }

    // Public functions to expose internal transient helpers for testing

    function getSolverOpsCalldataLength(
        uint256 userOpDataLength,
        uint256 msgDataLength
    )
        public
        pure
        returns (uint256 solverOpsLength)
    {
        return _getSolverOpsCalldataLength(userOpDataLength, msgDataLength);
    }
}
