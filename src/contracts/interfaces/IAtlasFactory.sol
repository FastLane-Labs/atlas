//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../types/UserCallTypes.sol";

interface IAtlasFactory {
    function createExecutionEnvironment(
        address account,
        address dAppControl
    )
        external
        returns (address executionEnvironment);

    function getOrCreateExecutionEnvironment(UserOperation calldata userOp)
        external
        returns (address executionEnvironment, DAppConfig memory dConfig);

    function getExecutionEnvironment(
        address user,
        address dAppControl
    )
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists);

    function getExecutionEnvironmentCustom(
        address user,
        bytes32 controlCodeHash,
        address controller,
        uint32 callConfig
    )
        external
        view
        returns (address executionEnvironment);

    function getMimicCreationCode(
        address controller,
        uint32 callConfig,
        address user,
        bytes32 controlCodeHash
    )
        external
        view
        returns (bytes memory creationCode);
}
