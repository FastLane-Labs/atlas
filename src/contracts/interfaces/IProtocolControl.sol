//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface IProtocolControl {
    function stagingCall(address to, address from, bytes4 userSelector, bytes calldata userData)
        external
        returns (bytes memory);

    function userLocalCall(bytes calldata data) external returns (bytes memory);

    function allocatingCall(bytes calldata data) external;

    function verificationCall(bytes calldata data) external returns (bool);

    function getProtocolCall() external view returns (ProtocolCall memory protocolCall);

    function getCallConfig() external view returns (bool, bool, bool, bool, bool, bool, bool, bool, bool);

    function getPayeeData(bytes calldata data) external returns (PayeeData[] memory);

    function getBidFormat(bytes calldata data) external returns (BidData[] memory);

    function getProtocolSignatory() external view returns (address governanceAddress);

    function requireSequencedNonces() external view returns (bool isSequenced);

    function stagingDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function userLocal() external view returns (bool local);

    function userDelegatedLocal() external view returns (bool delegated, bool local);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);
}
