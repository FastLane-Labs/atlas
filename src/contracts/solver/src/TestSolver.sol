// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {SolverBase} from "../SolverBase.sol";

// Flashbots opensource repo
import {BlindBackrun} from "./BlindBackrun.sol";

contract Solver is SolverBase, BlindBackrun {
    constructor(address atlasEscrow, address owner) SolverBase(atlasEscrow, owner) {}
}