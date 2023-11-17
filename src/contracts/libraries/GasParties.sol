//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Party, Ledger } from "../types/EscrowTypes.sol";
import { Lock, BaseLock, ExecutionPhase } from "../types/LockTypes.sol";

uint256 constant LEDGER_LENGTH = 5; // type(Party).max = 5

library PartyMath {
    function toBit(Party party) internal pure returns (uint256 partyBit) {
        partyBit = 1 << ((uint256(party) + 1));
    }

    function markActive(uint256 activeParties, Party party) internal pure returns (uint256) {
        return activeParties | 1 << ((uint256(party) + 1));
    }

    function markInactive(uint256 activeParties, Party party) internal pure returns (uint256) {
        return activeParties & ~(1 << ((uint256(party) + 1)));
    }

    function isActive(uint256 activeParties, Party party) internal pure returns (bool) {
        return activeParties & 1 << ((uint256(party) + 1)) != 0;
    }

    function isActive(uint256 activeParties, uint256 party) internal pure returns (bool) {
        return activeParties & 1 << (party + 1) != 0;
    }

    function isInactive(uint256 activeParties, Party party) internal pure returns (bool) {
        return activeParties & 1 << (uint256(party) + 1) == 0;
    }

    function isInactive(uint256 activeParties, uint256 party) internal pure returns (bool) {
        return activeParties & 1 << (party + 1) == 0;
    }

    function _getLedgerFromMemory(
        Ledger[LEDGER_LENGTH] memory meparties,
        Party party
    )
        internal
        pure
        returns (Ledger memory partyLedger, uint256 index)
    {
        uint256 partyIndex;

        do {
            partyIndex = uint256(party);
            partyLedger = meparties[partyIndex];
            party = partyLedger.proxy;
            index = uint256(party);
        } while (partyIndex != index);
    }

    uint256 internal constant _OFFSET = uint256(type(BaseLock).max) + 1;

    uint256 public constant VALID_PHASES_BUILDER_REQUEST = 0;
    uint256 public constant VALID_PHASES_BUILDER_CONTRIBUTION = 0;

    // Requests to Bundler (Bundler as donor)
    // NOTE: Bundler can only contribute via the transaction's value param, which can be requested at any stage
    // except during User or Solver ops
    uint256 public constant VALID_PHASES_BUNDLER_REQUEST = 1 << (_OFFSET + uint256(ExecutionPhase.Uninitialized))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PreOps)) | 1 << (_OFFSET + uint256(ExecutionPhase.PreSolver))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PostSolver)) | 1 << (_OFFSET + uint256(ExecutionPhase.HandlingPayments))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PostOps));

    // Contributions from Bundler (Bundler as donor)
    uint256 public constant VALID_PHASES_BUNDLER_CONTRIBUTION = 1 << (_OFFSET + uint256(ExecutionPhase.Uninitialized));

    // Requests to Solver (Solver as donor)
    // NOTE: Requests to Solver must occur before Solver operation execution.
    uint256 public constant VALID_PHASES_SOLVER_REQUEST = 1 << (_OFFSET + uint256(ExecutionPhase.PreOps))
        | 1 << (_OFFSET + uint256(ExecutionPhase.UserOperation)) | 1 << (_OFFSET + uint256(ExecutionPhase.PreSolver));

    // Contributions from Solver (Solver as donor)
    uint256 public constant VALID_PHASES_SOLVER_CONTRIBUTION = 1 << (_OFFSET + uint256(ExecutionPhase.SolverOperations));
    // TODO: Consider security risk of adding PostSolver.

    // Requests to User (User as donor)
    // NOTE: Requests to User must occur before User operation execution.
    // NOTE: These are expected to be rare and only used when the User is in a priveleged role (IE posting a proof)
    uint256 public constant VALID_PHASES_USER_REQUEST = 1 << (_OFFSET + uint256(ExecutionPhase.PreOps));

    // Contributions from User (User as donor)
    uint256 public constant VALID_PHASES_USER_CONTRIBUTION = 1 << (_OFFSET + uint256(ExecutionPhase.UserOperation));

    // Requests to DApp (DApp as donor)
    // NOTE: All of these would be initiated by the DApp
    uint256 public constant VALID_PHASES_DAPP_REQUEST = 1 << (_OFFSET + uint256(ExecutionPhase.Uninitialized))
        | 1 << (_OFFSET + uint256(ExecutionPhase.UserOperation)) | 1 << (_OFFSET + uint256(ExecutionPhase.PreOps))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PreSolver)); // No parties left to make a request to the DApp.

    // Contributions from DApp (DApp as donor)
    // NOTE: All of these would be initiated by the DApp
    uint256 public constant VALID_PHASES_DAPP_CONTRIBUTION = 1 << (_OFFSET + uint256(ExecutionPhase.Uninitialized))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PreOps)) | 1 << (_OFFSET + uint256(ExecutionPhase.PreSolver))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PostSolver)) | 1 << (_OFFSET + uint256(ExecutionPhase.HandlingPayments))
        | 1 << (_OFFSET + uint256(ExecutionPhase.PostOps));

    function validContribution(Party party, uint16 lockState) internal pure returns (bool) {
        uint256 pIndex = uint256(party);
        uint256 lock = uint256(lockState);

        // median index party = Solver
        if (pIndex > uint256(Party.Solver)) {
            if (pIndex == uint256(Party.DApp)) {
                // CASE: DAPP
                return lock & VALID_PHASES_DAPP_CONTRIBUTION != 0;
            } else {
                // CASE: USER
                return lock & VALID_PHASES_USER_CONTRIBUTION != 0;
            }
        } else if (pIndex == uint256(Party.Solver)) {
            // CASE: SOLVER
            return lock & VALID_PHASES_SOLVER_CONTRIBUTION != 0;
        } else if (pIndex == uint256(Party.Bundler)) {
            // CASE: BUNDLER
            return lock & VALID_PHASES_BUNDLER_CONTRIBUTION != 0;
        } else {
            // CASE: BUILDER
            return lock & VALID_PHASES_BUILDER_CONTRIBUTION != 0;
        }
    }

    function validRequest(Party party, uint16 lockState) internal pure returns (bool) {
        uint256 pIndex = uint256(party);
        uint256 lock = uint256(lockState);

        // median index party = Solver
        if (pIndex > uint256(Party.Solver)) {
            if (pIndex == uint256(Party.DApp)) {
                // CASE: DAPP
                return lock & VALID_PHASES_DAPP_REQUEST != 0;
            } else {
                // CASE: USER
                return lock & VALID_PHASES_USER_REQUEST != 0;
            }
        } else if (pIndex == uint256(Party.Solver)) {
            // CASE: SOLVER
            return lock & VALID_PHASES_SOLVER_REQUEST != 0;
        } else if (pIndex == uint256(Party.Bundler)) {
            // CASE: BUNDLER
            return lock & VALID_PHASES_BUNDLER_REQUEST != 0;
        } else {
            // CASE: BUILDER
            return lock & VALID_PHASES_BUILDER_REQUEST != 0;
        }
    }
}

/*
enum ExecutionPhase {
    Uninitialized,
    PreOps,
    UserOperation,
    PreSolver,
    SolverOperations,
    PostSolver,
    HandlingPayments,
    PostOps,
    Releasing
}
*/
