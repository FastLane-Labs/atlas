// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SolverBase} from "../SolverBase.sol";

// Flashbots opensource repo
import {BlindBackrun} from "./BlindBackrun/BlindBackrun.sol";

contract Solver is SolverBase, BlindBackrun {
    constructor(address weth9, address atlasEscrow, address owner) SolverBase(weth9, atlasEscrow, owner) {}
}