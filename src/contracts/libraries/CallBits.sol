//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IDAppControl } from "../interfaces/IDAppControl.sol";

import "../types/ConfigTypes.sol";

library CallBits {
    uint32 internal constant _ONE = uint32(1);

    function buildCallConfig(address control) internal view returns (uint32 callConfig) {
        callConfig = IDAppControl(control).CALL_CONFIG();
    }

    function encodeCallConfig(CallConfig memory callConfig) internal pure returns (uint32 encodedCallConfig) {
        if (callConfig.userNoncesSequential) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserNoncesSequential);
        }
        if (callConfig.dappNoncesSequential) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.DAppNoncesSequential);
        }
        if (callConfig.requirePreOps) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePreOps);
        }
        if (callConfig.trackPreOpsReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackPreOpsReturnData);
        }
        if (callConfig.trackUserReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackUserReturnData);
        }
        if (callConfig.delegateUser) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.DelegateUser);
        }
        if (callConfig.requirePreSolver) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePreSolver);
        }
        if (callConfig.requirePostSolver) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePostSolver);
        }
        if (callConfig.zeroSolvers) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ZeroSolvers);
        }
        if (callConfig.reuseUserOp) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ReuseUserOp);
        }
        if (callConfig.userAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserAuctioneer);
        }
        if (callConfig.solverAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.SolverAuctioneer);
        }
        if (callConfig.unknownAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UnknownAuctioneer);
        }
        if (callConfig.verifyCallChainHash) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.VerifyCallChainHash);
        }
        if (callConfig.forwardReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ForwardReturnData);
        }
        if (callConfig.requireFulfillment) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequireFulfillment);
        }
        if (callConfig.trustedOpHash) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrustedOpHash);
        }
        if (callConfig.invertBidValue) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.InvertBidValue);
        }
        if (callConfig.exPostBids) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ExPostBids);
        }
        if (callConfig.multipleSuccessfulSolvers) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.MultipleSuccessfulSolvers);
        }
        if (callConfig.checkMetacallGasLimit) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.CheckMetacallGasLimit);
        }
    }

    function decodeCallConfig(uint32 encodedCallConfig) internal pure returns (CallConfig memory callConfig) {
        callConfig.userNoncesSequential = needsSequentialUserNonces(encodedCallConfig);
        callConfig.dappNoncesSequential = needsSequentialDAppNonces(encodedCallConfig);
        callConfig.requirePreOps = needsPreOpsCall(encodedCallConfig);
        callConfig.trackPreOpsReturnData = needsPreOpsReturnData(encodedCallConfig);
        callConfig.trackUserReturnData = needsUserReturnData(encodedCallConfig);
        callConfig.delegateUser = needsDelegateUser(encodedCallConfig);
        callConfig.requirePreSolver = needsPreSolverCall(encodedCallConfig);
        callConfig.requirePostSolver = needsPostSolverCall(encodedCallConfig);
        callConfig.zeroSolvers = allowsZeroSolvers(encodedCallConfig);
        callConfig.reuseUserOp = allowsReuseUserOps(encodedCallConfig);
        callConfig.userAuctioneer = allowsUserAuctioneer(encodedCallConfig);
        callConfig.solverAuctioneer = allowsSolverAuctioneer(encodedCallConfig);
        callConfig.unknownAuctioneer = allowsUnknownAuctioneer(encodedCallConfig);
        callConfig.verifyCallChainHash = verifyCallChainHash(encodedCallConfig);
        callConfig.forwardReturnData = forwardReturnData(encodedCallConfig);
        callConfig.requireFulfillment = needsFulfillment(encodedCallConfig);
        callConfig.trustedOpHash = allowsTrustedOpHash(encodedCallConfig);
        callConfig.invertBidValue = invertsBidValue(encodedCallConfig);
        callConfig.exPostBids = exPostBids(encodedCallConfig);
        callConfig.multipleSuccessfulSolvers = multipleSuccessfulSolvers(encodedCallConfig);
        callConfig.checkMetacallGasLimit = checkMetacallGasLimit(encodedCallConfig);
    }

    function needsSequentialUserNonces(uint32 callConfig) internal pure returns (bool sequential) {
        sequential = callConfig & (1 << uint32(CallConfigIndex.UserNoncesSequential)) != 0;
    }

    function needsSequentialDAppNonces(uint32 callConfig) internal pure returns (bool sequential) {
        sequential = callConfig & (1 << uint32(CallConfigIndex.DAppNoncesSequential)) != 0;
    }

    function needsPreOpsCall(uint32 callConfig) internal pure returns (bool needsPreOps) {
        needsPreOps = callConfig & (1 << uint32(CallConfigIndex.RequirePreOps)) != 0;
    }

    function needsPreOpsReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = callConfig & (1 << uint32(CallConfigIndex.TrackPreOpsReturnData)) != 0;
    }

    function needsUserReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = callConfig & (1 << uint32(CallConfigIndex.TrackUserReturnData)) != 0;
    }

    function needsDelegateUser(uint32 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = callConfig & (1 << uint32(CallConfigIndex.DelegateUser)) != 0;
    }

    function needsPreSolverCall(uint32 callConfig) internal pure returns (bool needsPreSolver) {
        needsPreSolver = callConfig & (1 << uint32(CallConfigIndex.RequirePreSolver)) != 0;
    }

    function needsPostSolverCall(uint32 callConfig) internal pure returns (bool needsPostSolver) {
        needsPostSolver = callConfig & (1 << uint32(CallConfigIndex.RequirePostSolver)) != 0;
    }

    function allowsZeroSolvers(uint32 callConfig) internal pure returns (bool zeroSolvers) {
        zeroSolvers = callConfig & (1 << uint32(CallConfigIndex.ZeroSolvers)) != 0;
    }

    function allowsReuseUserOps(uint32 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = callConfig & (1 << uint32(CallConfigIndex.ReuseUserOp)) != 0;
    }

    function allowsUserAuctioneer(uint32 callConfig) internal pure returns (bool userAuctioneer) {
        userAuctioneer = callConfig & (1 << uint32(CallConfigIndex.UserAuctioneer)) != 0;
    }

    function allowsSolverAuctioneer(uint32 callConfig) internal pure returns (bool userAuctioneer) {
        userAuctioneer = callConfig & (1 << uint32(CallConfigIndex.SolverAuctioneer)) != 0;
    }

    function allowsUnknownAuctioneer(uint32 callConfig) internal pure returns (bool unknownAuctioneer) {
        unknownAuctioneer = callConfig & (1 << uint32(CallConfigIndex.UnknownAuctioneer)) != 0;
    }

    function verifyCallChainHash(uint32 callConfig) internal pure returns (bool verify) {
        verify = callConfig & (1 << uint32(CallConfigIndex.VerifyCallChainHash)) != 0;
    }

    function forwardReturnData(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.ForwardReturnData)) != 0;
    }

    function needsFulfillment(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.RequireFulfillment)) != 0;
    }

    function allowsTrustedOpHash(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.TrustedOpHash)) != 0;
    }

    function invertsBidValue(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.InvertBidValue)) != 0;
    }

    function exPostBids(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.ExPostBids)) != 0;
    }

    function multipleSuccessfulSolvers(uint32 callConfig) internal pure returns (bool) {
        return (callConfig & (1 << uint32(CallConfigIndex.MultipleSuccessfulSolvers))) != 0;
    }

    function checkMetacallGasLimit(uint32 callConfig) internal pure returns (bool) {
        return (callConfig & (1 << uint32(CallConfigIndex.CheckMetacallGasLimit))) != 0;
    }
}
