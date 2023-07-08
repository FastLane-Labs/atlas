//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct GovernanceData {
    address governance;
    uint16 callConfig; // bitwise
    uint64 lastUpdate;
}

struct ApproverSigningData {
    address governance; // signing on behalf of
    bool enabled; // EOA has been disabled if false
    uint64 nonce; // the highest nonce used so far. n+1 is always available
}
