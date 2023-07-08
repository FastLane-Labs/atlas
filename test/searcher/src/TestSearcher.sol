// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {SearcherBase} from "../../../src/contracts/searcher/SearcherBase.sol";

// Flashbots opensource repo
import {BlindBackrun} from "./blindBackrun.sol";

contract Searcher is SearcherBase, BlindBackrun {
    constructor(address atlasEscrow, address owner) SearcherBase(atlasEscrow, owner) {}
}
