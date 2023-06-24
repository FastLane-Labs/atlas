//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IProtocolControl {

    function stageCall(
        bytes calldata data
    ) external returns (bytes memory);

    function userLocalCall(
        bytes calldata data
    ) external returns (bytes memory);

    function allocatingCall(
        bytes calldata data
    ) external;

    function verificationCall(
        bytes calldata data
    ) external returns (bool);

    function stagingDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function userLocal() external view returns (bool local);

    function userDelegatedLocal() external view returns (bool delegated, bool local);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);

}