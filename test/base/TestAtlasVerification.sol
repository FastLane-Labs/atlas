//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../src/contracts/atlas/AtlasVerification.sol";

/// @title TestAtlasVerification
/// @author FastLane Labs
/// @notice A test version of the AtlasVerification to expose internal functions.
contract TestAtlasVerification is AtlasVerification {
    constructor(address atlas, address l2GasCalculator) AtlasVerification(atlas, l2GasCalculator) { }

    // Public functions to expose internal transient helpers for testing

    function getAndVerifyGasLimits(
        SolverOperation[] calldata solverOps,
        DAppConfig calldata dConfig,
        uint256 userOpGas,
        uint256 metacallGasLeft
    )
        public
        view
        returns (ValidCallsResult validCallsResult, uint256 allSolversGasLimit, uint256 bidFindOverhead)
    {
        return _getAndVerifyGasLimits(solverOps, dConfig, userOpGas, metacallGasLeft);
    }
}
