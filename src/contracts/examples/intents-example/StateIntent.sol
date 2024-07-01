//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

// Atlas Base Imports
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";

import "src/contracts/types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

import "forge-std/Test.sol";

// under construction

enum TimingPath {
    EarliestBlock,
    LatestBlock,
    ExactBlock,
    EarliestTime,
    LatestTime,
    ExactTime
}

struct Timing {
    TimingPath path;
    uint256 value;
}

enum StatePath {
    PriorAbsolute,
    PostAbsolute,
    PositiveDelta,
    NegativeDelta
}

struct StateExpression {
    StatePath path;
    uint8 offset;
    uint8 size;
    bytes32 slot;
    uint256 value;
}

struct StatePreference {
    address src;
    StateExpression[] exp;
}

struct Payment {
    address token;
    uint256 amount;
}

struct Intent {
    StatePreference[] preferences;
    Timing time;
    Payment pmt;
    address from;
}
