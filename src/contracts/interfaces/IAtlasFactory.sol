//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

interface AtlasFactory {

    function createExecutionEnvironment(address dAppControl) external returns (address executionEnvironment);

    function getExecutionEnvironment(address user, address dAppControl)
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists);

    function getMimicCreationCode(address controller, uint32 callConfig, address user, bytes32 controlCodeHash)
        external
        view
        returns (bytes memory creationCode);

}