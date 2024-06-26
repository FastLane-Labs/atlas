//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

library AccountingMath {
    // Gas Accounting public constants
    uint256 private constant _ATLAS_SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 private constant _BUNDLER_SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 private constant _SURCHARGE_SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 private constant _FIXED_GAS_OFFSET = 100_000;

    function withBundlerSurcharge(uint256 amount) internal pure returns (uint256 adjustedAmount) {
        adjustedAmount = amount * (_SURCHARGE_SCALE + _BUNDLER_SURCHARGE_RATE) / _SURCHARGE_SCALE;
    }

    function withoutBundlerSurcharge(uint256 amount) internal pure returns (uint256 unadjustedAmount) {
        unadjustedAmount = amount * _SURCHARGE_SCALE / (_SURCHARGE_SCALE + _BUNDLER_SURCHARGE_RATE);
    }

    function withAtlasAndBundlerSurcharges(uint256 amount) internal pure returns (uint256 adjustedAmount) {
        adjustedAmount =
            amount * (_SURCHARGE_SCALE + _ATLAS_SURCHARGE_RATE + _BUNDLER_SURCHARGE_RATE) / _SURCHARGE_SCALE;
    }

    // gets the Atlas surcharge from an unadjusted amount
    function getAtlasSurcharge(uint256 amount) internal pure returns (uint256 surcharge) {
        surcharge = amount * _ATLAS_SURCHARGE_RATE / _SURCHARGE_SCALE;
    }
}
