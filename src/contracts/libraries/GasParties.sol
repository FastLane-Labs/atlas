//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {GasParty} from "../types/EscrowTypes.sol";
import {Lock} from "../types/LockTypes.sol";

library GasPartyMath {

    function toBit(GasParty party) internal pure returns (uint256 partyBit) {
        partyBit = 1 << ((uint256(party) + 1));
    }

    function markActive(uint256 activeParties, GasParty party) internal pure returns (uint256) {
        return activeParties | 1 << ((uint256(party) + 1));
    }

    function isActive(uint256 activeParties, GasParty party) internal pure returns (bool) {
        return activeParties & 1 << ((uint256(party) + 1)) != 0;
    }

    function isActive(uint256 activeParties, uint256 party) internal pure returns (bool) {
        return activeParties & 1 << (party + 1) != 0;
    }

    function isInactive(uint256 activeParties, GasParty party) internal pure returns (bool) {
        return activeParties & 1 << (uint256(party) + 1) == 0;
    }

    function isInactive(uint256 activeParties, uint256 party) internal pure returns (bool) {
        return activeParties & 1 << (party + 1) == 0;
    }
}