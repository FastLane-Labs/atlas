//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";

interface IProtocolControl {
    function validateUserCall(UserMetaTx calldata userMetaTx) external view returns (bool);

    function stagingCall(UserMetaTx calldata userMetaTx) external returns (bytes memory);

    function userLocalCall(bytes calldata data) external returns (bytes memory);

    function allocatingCall(bytes calldata data) external;

    function searcherPreCall(bytes calldata data) external returns (bool);

    function searcherPostCall(bytes calldata data) external returns (bool);

    function verificationCall(bytes calldata data) external returns (bytes memory);

    function getProtocolCall() external view returns (ProtocolCall memory protocolCall);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function getPayeeData(bytes calldata data) external returns (PayeeData[] memory);

    function getBidFormat(UserMetaTx calldata userMetaTx) external view returns (BidData[] memory);

    function getBidValue(SearcherCall calldata searcherCall) external view returns (uint256);

    function getProtocolSignatory() external view returns (address governanceAddress);

    function requireSequencedNonces() external view returns (bool isSequenced);

    function stagingDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function userLocal() external view returns (bool local);

    function userDelegatedLocal() external view returns (bool delegated, bool local);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);
}
