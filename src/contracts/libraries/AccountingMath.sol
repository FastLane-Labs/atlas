//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

library AccountingMath {
    // Gas Accounting public constants
    uint256 internal constant _ATLAS_SURCHARGE_RATE = 1_000_000; // out of 10_000_000 = 10%
    uint256 internal constant _BUNDLER_SURCHARGE_RATE = 1_000_000; // out of 10_000_000 = 10%
    uint256 internal constant _SOLVER_GAS_LIMIT_BUFFER_PERCENTAGE = 500_000; // out of 10_000_000 = 5%
    uint256 internal constant _SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 internal constant _FIXED_GAS_OFFSET = 85_000;

    function withBundlerSurcharge(uint256 amount) internal pure returns (uint256 adjustedAmount) {
        adjustedAmount = amount * (_SCALE + _BUNDLER_SURCHARGE_RATE) / _SCALE;
    }

    function withoutBundlerSurcharge(uint256 amount) internal pure returns (uint256 unadjustedAmount) {
        unadjustedAmount = amount * _SCALE / (_SCALE + _BUNDLER_SURCHARGE_RATE);
    }

    function withAtlasAndBundlerSurcharges(uint256 amount) internal pure returns (uint256 adjustedAmount) {
        adjustedAmount = amount * (_SCALE + _ATLAS_SURCHARGE_RATE + _BUNDLER_SURCHARGE_RATE) / _SCALE;
    }

    // gets the Atlas surcharge from an unadjusted amount
    function getAtlasSurcharge(uint256 amount) internal pure returns (uint256 surcharge) {
        surcharge = amount * _ATLAS_SURCHARGE_RATE / _SCALE;
    }

    function getAtlasPortionFromTotalSurcharge(uint256 totalSurcharge) internal pure returns (uint256 atlasSurcharge) {
        atlasSurcharge = totalSurcharge * _ATLAS_SURCHARGE_RATE / (_ATLAS_SURCHARGE_RATE + _BUNDLER_SURCHARGE_RATE);
    }

    function solverGasLimitScaledDown(
        uint256 solverOpGasLimit,
        uint256 dConfigGasLimit
    )
        internal
        pure
        returns (uint256 gasLimit)
    {
        gasLimit = (solverOpGasLimit < dConfigGasLimit ? solverOpGasLimit : dConfigGasLimit) * _SCALE
            / (_SCALE + _SOLVER_GAS_LIMIT_BUFFER_PERCENTAGE);
    }
}
