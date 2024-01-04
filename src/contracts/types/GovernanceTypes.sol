//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

struct GovernanceData {
    address governance;
    uint32 callConfig; // bitwise
    uint64 lastUpdate;
}
