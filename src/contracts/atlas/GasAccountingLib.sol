//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {PartyMath} from "../libraries/GasParties.sol";
import {Storage} from "./Storage.sol";
import {FastLaneErrorsEvents} from "../types/Emissions.sol";

contract GasAccountingLib is Storage, FastLaneErrorsEvents {
    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _simulator
    ) Storage(_escrowDuration, _factory, _verification, _simulator) {}














    // Not needed in GasAccLib but set to keep in sync with Atlas
    function _computeDomainSeparator() internal virtual override view returns (bytes32) {
        return bytes32(0);
    }      
}