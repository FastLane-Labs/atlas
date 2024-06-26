//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IPermit69 {
    // NOTE: IPermit69 only works inside of the Atlas environment - specifically
    // inside of the custom ExecutionEnvironments that each user deploys when
    // interacting with Atlas in a manner controlled by the dApp.

    // The name comes from the reciprocal nature of the token transfers. Both
    // the user and the DAppControl can transfer tokens from the User
    // and the DAppControl contracts... but only if they each have granted
    // token approval to the Atlas main contract, and only during specific phases
    // of the Atlas execution process.

    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control,
        uint32 callConfig,
        uint8 phase
    )
        external;

    function transferDAppERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control,
        uint32 callConfig,
        uint8 phase
    )
        external;
}
