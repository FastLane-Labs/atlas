//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { DAppConfig } from "src/contracts/types/ConfigTypes.sol";
import { UserOperation } from "../types/UserOperation.sol";

interface IFactory {
    function createExecutionEnvironment(address dAppControl) external returns (address executionEnvironment);

    function getExecutionEnvironment(
        address user,
        address dAppControl
    )
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists);
}
