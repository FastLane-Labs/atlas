//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;


// NOTE: Experimental - Splitting contracts into [AtlETH, Atlas, AtlasFactory]

// AtlETH needs:
// ERC20 stuff - for the AtlETH token
// Permit2 integration - for external AtlETH use
// Permit69 - for internal approval between Atlas, Exec Envs, etc
// Escrow - locked down during phases of Atlas execution, or time locked
// GasAccounting - maybe?? Maybe in Atlas if msg.value needed
contract AtlETH2 {

}