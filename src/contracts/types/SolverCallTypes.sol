//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

bytes32 constant SOLVER_TYPEHASH = keccak256(
    "SolverOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 deadline,address dapp,address control,bytes32 userOpHash,address bidToken,uint256 bidAmount,bytes32 data)"
);

// NOTE: The calldata length of this SolverOperation struct is 608 bytes when the `data` field is excluded. This value
// is stored in the `_SOLVER_OP_BASE_CALLDATA` constant in Storage.sol and must be kept up-to-date with any changes to
// this struct.
struct SolverOperation {
    address from; // Solver EOA address
    address to; // Atlas address
    uint256 value;
    uint256 gas;
    uint256 maxFeePerGas; // maxFeePerGas solver is willing to pay.  This goes to validator, not dApp or user
    uint256 deadline;
    address solver; // Nested "to" address
    address control; // DAppControl address
    bytes32 userOpHash; // hash of User's Operation, for verification of user's tx (if not matched, solver wont be
        // charged for gas)
    address bidToken;
    uint256 bidAmount;
    bytes data;
    bytes signature;
}

struct SolverTracker {
    uint256 bidAmount;
    uint256 floor;
    uint256 ceiling;
    bool etherIsBidToken;
    bool invertsBidValue;
}