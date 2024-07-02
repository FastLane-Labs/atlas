// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SolverBase } from "../SolverBase.sol";

// Flashbots opensource repo
import { BlindBackrun } from "./BlindBackrun/BlindBackrun.sol";

contract Solver is SolverBase, BlindBackrun {
    constructor(address weth, address atlasEscrow, address owner) SolverBase(weth, atlasEscrow, owner) { }
}
