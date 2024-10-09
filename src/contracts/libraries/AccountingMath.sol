//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

library AccountingMath {
    // Gas Accounting public constants
    uint256 internal constant _SOLVER_GAS_LIMIT_BUFFER_PERCENTAGE = 500_000; // out of 10_000_000 = 5%
    uint256 internal constant _SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 internal constant _FIXED_GAS_OFFSET = 85_000;

    function withSurcharge(uint256 amount, uint256 surchargeRate) internal pure returns (uint256 adjustedAmount) {
        adjustedAmount = amount * (_SCALE + surchargeRate) / _SCALE;
    }

    function withoutSurcharge(uint256 amount, uint256 surchargeRate) internal pure returns (uint256 unadjustedAmount) {
        unadjustedAmount = amount * _SCALE / (_SCALE + surchargeRate);
    }

    function withSurcharges(
        uint256 amount,
        uint256 atlasSurchargeRate,
        uint256 bundlerSurchargeRate
    )
        internal
        pure
        returns (uint256 adjustedAmount)
    {
        adjustedAmount = amount * (_SCALE + atlasSurchargeRate + bundlerSurchargeRate) / _SCALE;
    }

    // gets the Atlas surcharge from an unadjusted amount
    function getSurcharge(
        uint256 unadjustedAmount,
        uint256 surchargeRate
    )
        internal
        pure
        returns (uint256 surchargeAmount)
    {
        surchargeAmount = unadjustedAmount * surchargeRate / _SCALE;
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
