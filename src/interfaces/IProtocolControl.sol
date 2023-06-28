//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {
    BidData,
    PayeeData
} from "../libraries/DataTypes.sol";

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

    function getCallConfig() external view returns (
        bool, bool, bool, bool, bool, bool, bool, bool
    );

    function getPayeeData(bytes calldata data) 
        external 
        returns (PayeeData[] memory);
    
    function getBidFormat(bytes calldata data) 
        external
        returns (BidData[] memory);

    function stagingDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function userLocal() external view returns (bool local);

    function userDelegatedLocal() external view returns (bool delegated, bool local);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);

}